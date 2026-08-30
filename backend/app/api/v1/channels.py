"""
API endpoints для каналов
"""
import json
import logging
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import String, and_, cast, func, or_
from typing import Optional, List
from redis.exceptions import ConnectionError as RedisConnectionError, TimeoutError as RedisTimeoutError
from app.core.database import get_db
from app.core.redis_client import redis_client
from app.api.dependencies import get_current_user_required, get_current_user
from app.models.user import User
from app.models.community import Channel
from app.models.community_member import ChannelMember
from app.models.post import Post
from app.models.post_view import PostView

logger = logging.getLogger(__name__)
from app.core.entitlements import HAN_CREATOR_REQUIRED_CODE
from app.services.subscription_service import SubscriptionService
from app.services.channel_membership_service import (
    MEMBER_STATUS_ACTIVE,
    MEMBER_STATUS_PENDING,
    active_member_channel_ids_subquery,
    can_view_channel_posts,
    channel_role_permissions,
    default_role_permissions,
    get_membership,
    has_channel_permission,
    is_channel_owner,
    membership_status_for_user,
    normalize_role_permissions,
    sync_channel_members_count,
)
from app.services.channel_posts_cache import invalidate_channel_posts_cache
from app.services.search_normalization import escaped_like_pattern, search_terms, stable_search_key
from app.schemas.channel import (
    CreateChannelRequest,
    UpdateChannelRequest,
    ChannelResponse,
    ChannelDetailResponse,
    JoinChannelResponse,
    ChannelMemberResponse,
    UpdateChannelMemberRoleRequest,
    ChannelNotificationsPatchRequest,
    ChannelInboxPrefsPatchRequest,
    ChannelInboxPrefsItem,
    ChannelInboxPrefsListResponse,
    ChannelJoinRequestResponse,
)
from app.schemas.post import CreatePostRequest, UpdatePostRequest, PostResponse

router = APIRouter()


def _require_can_view_posts(
    db: Session, channel: Channel, user: Optional[User]
) -> ChannelMember:
    member = get_membership(db, channel.id, user.id) if user else None
    from app.services.paid_features_service import PaidFeaturesService

    if not PaidFeaturesService(db).has_paid_channel_access(user.id if user else None, channel):
        if not user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Authentication required",
            )
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail={
                "code": "PAID_CHANNEL_REQUIRED",
                "message": "Для доступа к каналу нужна платная подписка",
                "price_stars": int(getattr(channel, "monthly_price_stars", 0) or 0),
            },
        )
    if not can_view_channel_posts(channel, user, member):
        if not user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Authentication required",
            )
        if member and member.status == MEMBER_STATUS_PENDING:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Membership pending approval",
            )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Channel is private",
        )
    return member


def assert_can_create_private_channel(is_public: bool, has_creator: bool) -> None:
    """Private channels require Creator/Pro (messenger product rule)."""
    if is_public is False and not has_creator:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": HAN_CREATOR_REQUIRED_CODE,
                "message": "Приватные каналы доступны с тарифом Creator или Pro",
            },
        )


def _post_preview_text(post: Post) -> str:
    title = (post.title or "").strip()
    if title:
        return title[:120]
    desc = (post.description or "").strip()
    if desc:
        return desc[:120]
    ptype = (post.type or "").lower()
    if ptype in ("reel", "video"):
        return "Видео"
    if ptype in ("photo", "image"):
        return "Фото"
    return "Новый пост"


def _batch_last_posts(db: Session, channel_ids: List[int]) -> dict:
    """Последний опубликованный пост на канал (один SQL-запрос)."""
    if not channel_ids:
        return {}
    rows = (
        db.query(Post)
        .filter(
            Post.channel_id.in_(channel_ids),
            Post.status == "published",
            Post.deleted_at.is_(None),
        )
        .order_by(Post.channel_id, Post.id.desc())
        .all()
    )
    out: dict = {}
    for post in rows:
        cid = post.channel_id
        if cid is None or cid in out:
            continue
        ts = post.published_at or post.created_at
        out[cid] = (_post_preview_text(post), ts)
    return out


def _build_channel_response(
    db: Session,
    channel: Channel,
    current_user: Optional[User],
) -> ChannelResponse:
    from app.services.channel_presentation_service import channel_presentation_fields
    from app.services.paid_features_service import PaidFeaturesService

    presentation = channel_presentation_fields(db, channel)
    paid_access = PaidFeaturesService(db).has_paid_channel_access(
        current_user.id if current_user else None,
        channel,
    )
    item = ChannelResponse.model_validate(channel).model_copy(
        update={**presentation, "paid_access": paid_access}
    )
    if not current_user:
        return item
    member = get_membership(db, channel.id, current_user.id)
    pending_count = None
    if has_channel_permission(channel, member, current_user, "manage_join_requests"):
        pending_count = (
            db.query(ChannelMember)
            .filter(
                ChannelMember.channel_id == channel.id,
                ChannelMember.status == MEMBER_STATUS_PENDING,
            )
            .count()
        )
    seen_posts_count = None
    is_favorite = None
    inbox_archived = None
    show_in_feed = None
    if member and member.status == MEMBER_STATUS_ACTIVE:
        seen_posts_count = member.last_seen_posts_count or 0
        is_favorite = bool(member.is_favorite)
        inbox_archived = bool(getattr(member, "inbox_archived", False))
        show_in_feed = bool(getattr(member, "show_in_feed", True))
    return item.model_copy(
        update={
            "membership_status": membership_status_for_user(
                member, channel, current_user
            ),
            "pending_join_requests_count": pending_count,
            "seen_posts_count": seen_posts_count,
            "is_favorite": is_favorite,
            "inbox_archived": inbox_archived,
            "show_in_feed": show_in_feed,
            "paid_access": paid_access,
            **presentation,
        }
    )


def _require_channel_permission(
    db: Session,
    channel: Channel,
    user: User,
    permission: str,
    detail: str = "Недостаточно прав для действия",
) -> ChannelMember:
    member = get_membership(db, channel.id, user.id)
    if not has_channel_permission(channel, member, user, permission):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=detail,
        )
    return member


@router.post("", response_model=ChannelResponse, status_code=status.HTTP_201_CREATED)
async def create_channel(
    request: CreateChannelRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Создать канал"""
    import logging
    logger = logging.getLogger(__name__)
    
    try:
        # Проверяем уникальность slug
        existing = db.query(Channel).filter(Channel.slug == request.slug).first()
        if existing:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Channel with this slug already exists"
            )
        
        is_public = request.is_public if request.is_public is not None else True
        has_tools = SubscriptionService(db).has_entitlement(
            current_user.id, "creator_tools"
        )
        assert_can_create_private_channel(is_public, has_tools)

        # Создаем канал
        channel = Channel(
            name=request.name,
            slug=request.slug,
            description=request.description,
            cover_url=request.cover_url,
            avatar_url=request.avatar_url,
            admin_user_id=current_user.id,
            is_public=is_public,
            recipe_visibility_mode="mixed",  # legacy DB column
            category=request.category,
            tags=request.tags if request.tags is not None else [],
            members_count=1,  # Админ автоматически становится участником
            posts_count=0,
            auto_publish_to_feed=True,
            auto_publish_to_menu=False,
            allow_comments=True,
            allow_likes=True,
            allow_reposts=True,
            role_permissions=default_role_permissions(),
            auto_publish_reels=request.auto_publish_reels,
            is_paid=bool(request.is_paid),
            monthly_price_stars=max(0, int(request.monthly_price_stars or 0)),
        )
        
        db.add(channel)
        db.commit()
        db.refresh(channel)
        
        # Добавляем владельца как участника с ролью "owner"
        member = ChannelMember(
            channel_id=channel.id,
            user_id=current_user.id,
            role="owner",
            status=MEMBER_STATUS_ACTIVE,
        )
        db.add(member)
        db.commit()
        db.refresh(channel)
        
        try:
            return ChannelResponse.model_validate(channel)
        except Exception as e:
            logger.error(f"Error validating created channel: {e}", exc_info=True)
            # Возвращаем базовую информацию
            return ChannelResponse(
                id=channel.id,
                name=channel.name,
                slug=channel.slug,
                description=channel.description,
                cover_url=channel.cover_url,
                avatar_url=channel.avatar_url,
                admin_user_id=channel.admin_user_id,
                is_public=channel.is_public,
                category=channel.category,
                tags=channel.tags if channel.tags is not None else [],
                members_count=channel.members_count if channel.members_count is not None else 1,
                posts_count=channel.posts_count if channel.posts_count is not None else 0,
                created_at=channel.created_at,
                auto_publish_reels=channel.auto_publish_reels,
            )
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        logger.error(f"Error creating channel: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create channel: {str(e)}"
        )


@router.put("/{channel_id}", response_model=ChannelResponse)
async def update_channel(
    channel_id: int,
    request: UpdateChannelRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Обновить канал (только владелец или админ)"""
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Channel not found"
        )
    
    member = get_membership(db, channel_id, current_user.id)
    if not has_channel_permission(
        channel, member, current_user, "manage_channel_settings"
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Недостаточно прав для изменения настроек канала",
        )
    
    # Проверяем уникальность slug (если изменился)
    if request.slug and request.slug != channel.slug:
        existing = db.query(Channel).filter(Channel.slug == request.slug).first()
        if existing:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Channel with this slug already exists"
            )
    
    # Обновляем поля (только переданные)
    if request.name is not None:
        channel.name = request.name
    if request.slug is not None:
        channel.slug = request.slug
    if request.description is not None:
        channel.description = request.description
    if request.cover_url is not None:
        channel.cover_url = request.cover_url
    if request.avatar_url is not None:
        channel.avatar_url = request.avatar_url
    has_tools = SubscriptionService(db).has_entitlement(
        current_user.id, "creator_tools"
    )
    if request.is_public is not None:
        assert_can_create_private_channel(request.is_public, has_tools)
        channel.is_public = request.is_public
    if request.category is not None:
        channel.category = request.category
    if request.tags is not None:
        channel.tags = request.tags
    if request.rules is not None:
        channel.rules = request.rules
    if request.auto_publish_to_feed is not None:
        channel.auto_publish_to_feed = request.auto_publish_to_feed
    if request.allow_comments is not None:
        channel.allow_comments = request.allow_comments
    if request.allow_likes is not None:
        channel.allow_likes = request.allow_likes
    if request.allow_reposts is not None:
        channel.allow_reposts = request.allow_reposts
    if request.auto_publish_reels is not None:
        channel.auto_publish_reels = request.auto_publish_reels
    if request.is_paid is not None:
        channel.is_paid = bool(request.is_paid)
    if request.monthly_price_stars is not None:
        channel.monthly_price_stars = max(0, int(request.monthly_price_stars or 0))
    if request.role_permissions is not None:
        if not is_channel_owner(channel, current_user):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Только владелец канала может менять права ролей",
            )
        channel.role_permissions = normalize_role_permissions(request.role_permissions)
    if request.accent_color is not None:
        if not has_creator:
            from app.core.entitlements import HAN_CREATOR_REQUIRED_CODE

            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={
                    "code": HAN_CREATOR_REQUIRED_CODE,
                    "message": "Оформление канала доступно с тарифом Creator или Pro",
                },
            )
        color = (request.accent_color or "").strip()
        channel.accent_color = color or None

    db.commit()
    db.refresh(channel)
    
    try:
        return ChannelResponse.model_validate(channel)
    except Exception as e:
        import logging
        logger = logging.getLogger(__name__)
        logger.error(f"Error validating updated channel: {e}", exc_info=True)
        # Возвращаем базовую информацию
        return ChannelResponse(
            id=channel.id,
            name=channel.name,
            slug=channel.slug,
            description=channel.description,
            cover_url=channel.cover_url,
            avatar_url=channel.avatar_url,
            admin_user_id=channel.admin_user_id,
            is_public=channel.is_public,
            category=channel.category,
            tags=channel.tags if channel.tags is not None else [],
            members_count=channel.members_count if channel.members_count is not None else 0,
            posts_count=channel.posts_count if channel.posts_count is not None else 0,
            created_at=channel.created_at,
            auto_publish_reels=channel.auto_publish_reels,
        )


@router.get("/inbox-unread-count")
async def channel_inbox_unread_count(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Сумма непрочитанных постов в каналах пользователя (inbox)."""
    rows = (
        db.query(Channel.posts_count, ChannelMember.last_seen_posts_count)
        .join(ChannelMember, ChannelMember.channel_id == Channel.id)
        .filter(
            ChannelMember.user_id == current_user.id,
            ChannelMember.status == MEMBER_STATUS_ACTIVE,
        )
        .all()
    )
    total = 0
    for posts_count, seen in rows:
        posts = posts_count or 0
        seen_n = seen or 0
        delta = posts - seen_n
        if delta > 0:
            total += delta
    return {"count": total}


@router.get("/inbox-prefs", response_model=ChannelInboxPrefsListResponse)
async def list_channel_inbox_prefs(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Настройки inbox для всех каналов пользователя (синхронизация между устройствами)."""
    rows = (
        db.query(ChannelMember)
        .filter(
            ChannelMember.user_id == current_user.id,
            ChannelMember.status == MEMBER_STATUS_ACTIVE,
        )
        .all()
    )
    items = [
        ChannelInboxPrefsItem(
            channel_id=m.channel_id,
            is_favorite=bool(m.is_favorite),
            inbox_archived=bool(getattr(m, "inbox_archived", False)),
            show_in_feed=bool(getattr(m, "show_in_feed", True)),
            notifications_enabled=bool(getattr(m, "notifications_enabled", True)),
        )
        for m in rows
    ]
    return ChannelInboxPrefsListResponse(items=items)


@router.patch("/{channel_id}/inbox-prefs")
async def patch_channel_inbox_prefs(
    channel_id: int,
    body: ChannelInboxPrefsPatchRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Обновить избранное, архив inbox, показ в ленте, уведомления."""
    member = (
        db.query(ChannelMember)
        .filter(
            ChannelMember.channel_id == channel_id,
            ChannelMember.user_id == current_user.id,
            ChannelMember.status == MEMBER_STATUS_ACTIVE,
        )
        .first()
    )
    if not member:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Not a member of this channel",
        )
    if body.is_favorite is not None:
        member.is_favorite = body.is_favorite
    if body.inbox_archived is not None:
        member.inbox_archived = body.inbox_archived
    if body.show_in_feed is not None:
        member.show_in_feed = body.show_in_feed
    if body.notifications_enabled is not None:
        member.notifications_enabled = body.notifications_enabled
    db.commit()
    return ChannelInboxPrefsItem(
        channel_id=member.channel_id,
        is_favorite=bool(member.is_favorite),
        inbox_archived=bool(getattr(member, "inbox_archived", False)),
        show_in_feed=bool(getattr(member, "show_in_feed", True)),
        notifications_enabled=bool(getattr(member, "notifications_enabled", True)),
    )


@router.get("/{channel_id}", response_model=ChannelDetailResponse)
async def get_channel(
    channel_id: int,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user)
):
    """Получить информацию о канале"""
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Channel not found"
        )
    
    member = (
        get_membership(db, channel_id, current_user.id) if current_user else None
    )
    m_status = membership_status_for_user(member, channel, current_user)
    from app.services.paid_features_service import PaidFeaturesService

    paid_access = PaidFeaturesService(db).has_paid_channel_access(
        current_user.id if current_user else None,
        channel,
    )
    can_posts = can_view_channel_posts(channel, current_user, member) and paid_access

    is_member = m_status == MEMBER_STATUS_ACTIVE
    is_owner = is_channel_owner(channel, current_user)
    is_admin = is_owner or (
        member is not None
        and member.status == MEMBER_STATUS_ACTIVE
        and member.role == "admin"
    )
    is_moderator = (
        member is not None
        and member.status == MEMBER_STATUS_ACTIVE
        and member.role == "moderator"
    )
    channel_notifications_enabled = None
    if is_member and member:
        channel_notifications_enabled = bool(
            getattr(member, "notifications_enabled", True)
        )

    pending_count = None
    if current_user and has_channel_permission(
        channel, member, current_user, "manage_join_requests"
    ):
        pending_count = (
            db.query(ChannelMember)
            .filter(
                ChannelMember.channel_id == channel_id,
                ChannelMember.status == MEMBER_STATUS_PENDING,
            )
            .count()
        )

    admin = db.query(User).filter(User.id == channel.admin_user_id).first()
    from app.services.channel_presentation_service import channel_presentation_fields

    presentation = channel_presentation_fields(db, channel)

    return ChannelDetailResponse(
        id=channel.id,
        name=channel.name,
        slug=channel.slug,
        description=channel.description,
        cover_url=channel.cover_url,
        avatar_url=channel.avatar_url,
        admin_user_id=channel.admin_user_id,
        is_public=channel.is_public,
        category=channel.category,
        tags=channel.tags if channel.tags is not None else [],
        rules=channel.rules,
        recipe_visibility_mode=channel.recipe_visibility_mode or "mixed",
        auto_publish_to_feed=channel.auto_publish_to_feed if channel.auto_publish_to_feed is not None else True,
        auto_publish_to_menu=channel.auto_publish_to_menu if channel.auto_publish_to_menu is not None else False,
        allow_comments=channel.allow_comments if channel.allow_comments is not None else True,
        allow_likes=channel.allow_likes if channel.allow_likes is not None else True,
        allow_reposts=channel.allow_reposts if channel.allow_reposts is not None else True,
        role_permissions=channel_role_permissions(channel),
        is_owner=is_owner,
        is_moderator=is_moderator,
        members_count=channel.members_count if channel.members_count is not None else 0,
        posts_count=channel.posts_count if channel.posts_count is not None else 0,
        is_paid=bool(getattr(channel, "is_paid", False)),
        monthly_price_stars=int(getattr(channel, "monthly_price_stars", 0) or 0),
        paid_access=paid_access,
        created_at=channel.created_at,
        admin_user={
            "id": admin.id,
            "name": admin.name,
            "username": admin.username,
            "avatar_url": admin.avatar_url,
        } if admin else None,
        is_member=is_member,
        is_admin=is_admin,
        channel_notifications_enabled=channel_notifications_enabled,
        membership_status=m_status,
        can_view_posts=can_posts,
        pending_join_requests_count=pending_count,
        has_creator_badge=presentation["has_creator_badge"],
        accent_color=presentation["accent_color"],
    )


@router.get("", response_model=dict)
async def list_channels(
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    search: Optional[str] = Query(None, description="Поиск по названию и описанию"),
    subscribed: Optional[bool] = Query(None, description="Мои каналы (требует авторизации)"),
    mine: Optional[bool] = Query(None, description="Каналы, где я создатель (включая приватные)"),
    recommended: Optional[bool] = Query(None, description="Рекомендованные каналы"),
    catalog: Optional[bool] = Query(None, description="Каталог всех каналов"),
    category: Optional[str] = Query(None, description="Фильтр по категории/тематике"),
    sort: Optional[str] = Query("popular", description="Сортировка: popular, new, members, activity, posts"),
    min_subscribers: Optional[int] = Query(None, description="Минимальное количество подписчиков"),
    max_subscribers: Optional[int] = Query(None, description="Максимальное количество подписчиков"),
    has_recipes: Optional[bool] = Query(None, description="Только каналы с рецептами"),
    min_posts: Optional[int] = Query(None, description="Минимальное количество постов"),
    with_last_post: Optional[bool] = Query(
        None, description="Добавить превью последнего поста (для списка чатов)"
    ),
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user)
):
    """
    Получить список каналов
    
    Параметры:
    - subscribed: Мои каналы (каналы, на которые подписан пользователь)
    - recommended: Рекомендованные каналы
    - catalog: Каталог всех каналов (по умолчанию)
    - category: Фильтр по категории
    - sort: Сортировка (popular, new, members)
    """
    # Каналы, где пользователь создатель (публичные и приватные)
    if mine:
        if not current_user:
            return {"items": [], "total": 0}
        query = (
            db.query(Channel)
            .filter(Channel.admin_user_id == current_user.id)
            .order_by(Channel.created_at.desc())
        )
    # Участник или создатель (подписки + свои каналы)
    elif subscribed:
        if not current_user:
            return {"items": [], "total": 0}
        member_channel_ids = (
            db.query(ChannelMember.channel_id)
            .filter(
                ChannelMember.user_id == current_user.id,
                ChannelMember.status == MEMBER_STATUS_ACTIVE,
            )
        )
        query = db.query(Channel).filter(
            or_(
                Channel.id.in_(member_channel_ids),
                Channel.admin_user_id == current_user.id,
            )
        ).order_by(Channel.created_at.desc())
    elif recommended:
        query = db.query(Channel).filter(Channel.is_public.is_(True))
    elif search and search.strip():
        term = f"%{search.strip()}%"
        query = db.query(Channel).filter(
            or_(
                Channel.name.ilike(term),
                Channel.slug.ilike(term),
            )
        )
    else:
        query = db.query(Channel).filter(Channel.is_public.is_(True))

    # Рекомендованные (улучшенный алгоритм)
    if recommended:
        if current_user:
            # Исключаем каналы, на которые пользователь уже подписан
            subscribed_channel_ids = active_member_channel_ids_subquery(
                db, current_user.id
            )
            query = query.filter(
                ~Channel.id.in_(subscribed_channel_ids),
                Channel.admin_user_id != current_user.id,
            )
            
            # Улучшенный алгоритм рекомендаций:
            # 1. Приоритет каналам с активностью за последние 7 дней
            # 2. Учитываем категории каналов, на которые пользователь уже подписан
            # 3. Приоритет новым каналам (созданным за последние 30 дней)
            # 4. Балансируем популярность и свежесть
            
            # Получаем категории каналов, на которые пользователь подписан
            subscribed_categories = db.query(Channel.category).join(
                ChannelMember
            ).filter(
                ChannelMember.user_id == current_user.id,
                ChannelMember.status == MEMBER_STATUS_ACTIVE,
                Channel.category.isnot(None),
            ).distinct().all()
            subscribed_categories_list = [cat[0] for cat in subscribed_categories if cat[0]]
            
            # Если есть подписки по категориям, приоритет каналам с такими же категориями
            # (но не обязательно - просто добавляем вес)
            # Для простоты пока используем комбинированную сортировку:
            # - Новые каналы (созданные за последние 30 дней) получают бонус
            # - Популярные каналы (много участников и постов)
            # - Активные каналы (много постов за последнее время)
            
            from datetime import datetime, timedelta
            from sqlalchemy import case
            
            # Вычисляем "рейтинг рекомендации"
            # Комбинация: популярность + свежесть + активность
            thirty_days_ago = datetime.utcnow() - timedelta(days=30)
            is_recent = case(
                (Channel.created_at >= thirty_days_ago, 1),
                else_=0
            )
            
            # Сортируем по комбинированному рейтингу:
            # (members_count * 0.4 + posts_count * 0.4 + is_recent * 100) * (1 + category_bonus)
            # Для простоты используем более простую формулу
            query = query.order_by(
                (Channel.members_count * 0.4 + Channel.posts_count * 0.6 + is_recent * 50).desc(),
                Channel.created_at.desc()  # Вторичная сортировка по дате создания
            )
        else:
            # Для неавторизованных пользователей - просто популярные каналы
            query = query.order_by(Channel.members_count.desc(), Channel.posts_count.desc())
    # Каталог (по умолчанию)
    else:
        if sort == "new":
            query = query.order_by(Channel.created_at.desc())
        elif sort == "members":
            query = query.order_by(Channel.members_count.desc())
        elif sort == "activity":
            # Сортировка по активности (последний пост)
            from app.models.post import Post
            from datetime import datetime, timedelta
            # Подзапрос для получения даты последнего поста
            last_post_subq = db.query(
                func.max(Post.published_at).label('last_post_date'),
                Post.channel_id
            ).filter(
                Post.channel_id.isnot(None),
                Post.status == "published",
                Post.deleted_at.is_(None)
            ).group_by(Post.channel_id).subquery()
            
            query = query.outerjoin(
                last_post_subq, Channel.id == last_post_subq.c.channel_id
            ).order_by(
                last_post_subq.c.last_post_date.desc().nulls_last(),
                Channel.posts_count.desc()
            )
        elif sort == "posts":
            query = query.order_by(Channel.posts_count.desc())
        else:  # popular (по умолчанию)
            query = query.order_by(Channel.members_count.desc(), Channel.posts_count.desc())
    
    # Фильтр по категории
    if category:
        query = query.filter(Channel.category == category)
    
    # Поиск по названию, описанию и тегам
    if search:
        search_term = f"%{search}%"
        # Поиск по названию и описанию
        search_filter = (
            (Channel.name.ilike(search_term)) |
            (Channel.description.ilike(search_term))
        )
        # Поиск по тегам (если теги не None)
        # Для PostgreSQL ARRAY используем строковое представление
        try:
            # Преобразуем массив тегов в строку для поиска
            tags_search = func.array_to_string(Channel.tags, ',').ilike(search_term)
            search_filter = search_filter | tags_search
        except Exception:
            # Если не удалось, используем только базовый поиск
            pass
        
        query = query.filter(search_filter)
    
    total = query.count()
    channels = query.limit(limit).offset(offset).all()
    
    # Безопасное преобразование каналов в ответ
    items = []
    for ch in channels:
        try:
            items.append(_build_channel_response(db, ch, current_user))
        except Exception as e:
            # Логируем ошибку, но продолжаем обработку других каналов
            import logging
            logger = logging.getLogger(__name__)
            logger.error(f"Error validating channel {ch.id}: {e}", exc_info=True)
            # Пропускаем проблемный канал
            continue
    
    if with_last_post and items:
        previews = _batch_last_posts(db, [ch.id for ch in items])
        enriched = []
        for ch in items:
            preview = previews.get(ch.id)
            if preview:
                enriched.append(
                    ch.model_copy(
                        update={
                            "last_post_preview": preview[0],
                            "last_post_at": preview[1],
                        }
                    )
                )
            else:
                enriched.append(ch)
        items = enriched

    return {
        "items": items,
        "total": total,
    }


@router.post("/{channel_id}/join", response_model=JoinChannelResponse)
async def join_channel(
    channel_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Присоединиться к каналу"""
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Channel not found"
        )
    
    # Проверяем, не является ли уже участником
    existing = db.query(ChannelMember).filter(
        ChannelMember.channel_id == channel_id,
        ChannelMember.user_id == current_user.id
    ).first()
    
    if existing:
        if existing.status == MEMBER_STATUS_PENDING:
            return JoinChannelResponse(
                joined=False,
                pending=True,
                members_count=channel.members_count or 0,
                membership_status=MEMBER_STATUS_PENDING,
            )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Already a member of this channel",
        )

    if channel.is_public:
        member_status = MEMBER_STATUS_ACTIVE
    else:
        member_status = MEMBER_STATUS_PENDING

    member = ChannelMember(
        channel_id=channel_id,
        user_id=current_user.id,
        role="member",
        status=member_status,
    )
    db.add(member)

    if member_status == MEMBER_STATUS_ACTIVE:
        sync_channel_members_count(db, channel_id)
    db.commit()
    db.refresh(channel)

    return JoinChannelResponse(
        joined=member_status == MEMBER_STATUS_ACTIVE,
        pending=member_status == MEMBER_STATUS_PENDING,
        members_count=channel.members_count or 0,
        membership_status=member_status,
    )


@router.delete("/{channel_id}/join", response_model=JoinChannelResponse)
async def leave_channel(
    channel_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Покинуть канал"""
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Channel not found"
        )
    
    # Проверяем, является ли участником
    member = db.query(ChannelMember).filter(
        ChannelMember.channel_id == channel_id,
        ChannelMember.user_id == current_user.id
    ).first()
    
    if not member:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Not a member of this channel"
        )
    
    if member.role in ("owner", "admin"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Owner or admin cannot leave channel. Transfer rights or delete channel.",
        )

    db.delete(member)
    sync_channel_members_count(db, channel_id)
    db.commit()
    db.refresh(channel)

    return JoinChannelResponse(
        joined=False,
        pending=False,
        members_count=channel.members_count or 0,
        membership_status="none",
    )


@router.get(
    "/{channel_id}/join-requests",
    response_model=dict,
)
async def list_channel_join_requests(
    channel_id: int,
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Заявки на вступление в приватный канал (для владельца / админа / модератора)."""
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Channel not found",
        )
    _require_channel_permission(
        db,
        channel,
        current_user,
        "manage_join_requests",
        "Недостаточно прав для просмотра заявок на подписку",
    )

    rows = (
        db.query(ChannelMember, User)
        .join(User, ChannelMember.user_id == User.id)
        .filter(
            ChannelMember.channel_id == channel_id,
            ChannelMember.status == MEMBER_STATUS_PENDING,
        )
        .order_by(ChannelMember.joined_at.asc())
        .limit(limit)
        .offset(offset)
        .all()
    )
    total = (
        db.query(func.count(ChannelMember.id))
        .filter(
            ChannelMember.channel_id == channel_id,
            ChannelMember.status == MEMBER_STATUS_PENDING,
        )
        .scalar()
        or 0
    )
    items = []
    for m, u in rows:
        items.append(
            ChannelJoinRequestResponse(
                id=m.id,
                user_id=m.user_id,
                channel_id=m.channel_id,
                joined_at=m.joined_at,
                user={
                    "id": u.id,
                    "name": u.name,
                    "username": u.username,
                    "avatar_url": u.avatar_url,
                },
            )
        )
    return {"items": items, "total": total}


@router.post(
    "/{channel_id}/join-requests/{user_id}/approve",
    response_model=JoinChannelResponse,
)
async def approve_channel_join_request(
    channel_id: int,
    user_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Channel not found",
        )
    _require_channel_permission(
        db,
        channel,
        current_user,
        "manage_join_requests",
        "Недостаточно прав для одобрения заявок на подписку",
    )

    pending = get_membership(db, channel_id, user_id)
    if not pending or pending.status != MEMBER_STATUS_PENDING:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Join request not found",
        )
    pending.status = MEMBER_STATUS_ACTIVE
    sync_channel_members_count(db, channel_id)
    db.commit()
    db.refresh(channel)

    try:
        from app.models.notification import Notification

        db.add(
            Notification(
                user_id=user_id,
                type="channel_join_approved",
                entity_type="channel",
                entity_id=channel_id,
                actor_id=current_user.id,
                title=f"Вас приняли в канал «{channel.name}»",
                body="Теперь доступны все публикации канала.",
                data={"channel_id": channel_id, "channel_name": channel.name},
                is_read=False,
            )
        )
        db.commit()
    except Exception as e:
        logger.warning("Failed to notify user about join approval: %s", e)

    return JoinChannelResponse(
        joined=True,
        pending=False,
        members_count=channel.members_count or 0,
        membership_status=MEMBER_STATUS_ACTIVE,
    )


@router.post(
    "/{channel_id}/join-requests/{user_id}/reject",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def reject_channel_join_request(
    channel_id: int,
    user_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Channel not found",
        )
    _require_channel_permission(
        db,
        channel,
        current_user,
        "manage_join_requests",
        "Недостаточно прав для отклонения заявок на подписку",
    )

    pending = get_membership(db, channel_id, user_id)
    if not pending or pending.status != MEMBER_STATUS_PENDING:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Join request not found",
        )
    db.delete(pending)
    db.commit()
    return None


@router.post("/{channel_id}/inbox-read")
async def mark_channel_inbox_read(
    channel_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Отметить посты канала просмотренными в inbox (синхронизация между устройствами)."""
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Channel not found",
        )
    member = get_membership(db, channel_id, current_user.id)
    if not member or member.status != MEMBER_STATUS_ACTIVE:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not a member of this channel",
        )
    posts_count = channel.posts_count or 0
    seen = member.last_seen_posts_count or 0
    if posts_count > seen:
        member.last_seen_posts_count = posts_count
        db.commit()
    return {"ok": True, "seen_posts_count": member.last_seen_posts_count or 0}


@router.patch("/{channel_id}/notifications")
async def patch_channel_notifications(
    channel_id: int,
    body: ChannelNotificationsPatchRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Включить/выключить уведомления о постах канала (для подписчика)."""
    member = db.query(ChannelMember).filter(
        ChannelMember.channel_id == channel_id,
        ChannelMember.user_id == current_user.id,
    ).first()
    if not member or member.status != MEMBER_STATUS_ACTIVE:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Not a member of this channel",
        )
    member.notifications_enabled = body.enabled
    db.commit()
    return {"enabled": body.enabled}


@router.get("/{channel_id}/posts")
async def get_channel_posts(
    channel_id: int,
    post_type: Optional[str] = Query(None, description="Filter by post type: text, photo, recipe, reel"),
    search: Optional[str] = Query(None, description="Search by title, description, tags and recipe text"),
    fresh: bool = Query(False, description="Skip Redis first-page cache after a write"),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user)
):
    """
    Получить посты канала (с фильтрацией по типу)
    
    Оптимизировано с кэшированием и batch loading для быстрой загрузки.
    """
    # Создаем ключ кэша
    normalized_search = stable_search_key(search or "")
    cache_key = f"channel_posts:{channel_id}:{post_type or 'all'}:{normalized_search or 'no_search'}:{limit}:{offset}"
    if current_user:
        cache_key += f":user_{current_user.id}"
    
    # Проверяем кэш (только для offset=0, чтобы не кэшировать все страницы)
    if offset == 0 and not fresh:
        try:
            cached = redis_client.get(cache_key)
            if cached:
                logger.info(f"✅ Используем кэш для постов канала: {cache_key}")
                return json.loads(cached)
        except (RedisConnectionError, RedisTimeoutError) as e:
            logger.warning(f"Redis недоступен для кэша: {e}")
        except Exception as e:
            logger.warning(f"Ошибка чтения кэша: {e}")
    
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Channel not found"
        )
    
    _require_can_view_posts(db, channel, current_user)

    # Получаем посты с фильтрацией по типу
    query = db.query(Post).filter(
        Post.channel_id == channel_id,
        Post.status == "published",
        Post.deleted_at.is_(None)
    )
    
    # Фильтр по типу поста
    if post_type:
        query = query.filter(Post.type == post_type)

    if normalized_search:
        tags_text = func.coalesce(func.array_to_string(Post.tags, ' '), '')
        ingredients_text = func.coalesce(cast(Post.body["ingredients"], String), '')
        steps_text = func.coalesce(cast(Post.body["steps"], String), '')

        term_filters = []
        for term in search_terms(normalized_search):
            pattern = escaped_like_pattern(term)
            term_filters.append(
                or_(
                    func.coalesce(Post.title, '').ilike(pattern, escape='\\'),
                    func.coalesce(Post.description, '').ilike(pattern, escape='\\'),
                    tags_text.ilike(pattern, escape='\\'),
                    ingredients_text.ilike(pattern, escape='\\'),
                    steps_text.ilike(pattern, escape='\\'),
                )
            )
        if term_filters:
            query = query.filter(and_(*term_filters))
    
    # Закреплённые сверху, затем по дате публикации (новые первыми)
    posts = (
        query.order_by(Post.is_pinned.desc(), Post.published_at.desc())
        .limit(limit)
        .offset(offset)
        .all()
    )
    
    # Подсчет общего количества
    total = query.count()
    
    if not posts:
        return {
            "posts": [],
            "total": 0,
        }
    
    # Оптимизация: batch loading для метаданных (устраняем N+1 проблему)
    from app.models.like import Like
    from app.models.comment import Comment
    from app.schemas.post import PostResponse
    
    post_ids = [post.id for post in posts]
    
    # Batch loading лайков (один запрос для всех постов)
    likes_counts = {}
    if post_ids:
        likes_subquery = db.query(
            Like.post_id,
            func.count(Like.id).label('count')
        ).filter(
            Like.post_id.in_(post_ids)
        ).group_by(Like.post_id).all()
        
        for post_id, count in likes_subquery:
            likes_counts[post_id] = count
    
    # Batch loading комментариев (один запрос для всех постов)
    comments_counts = {}
    if post_ids:
        comments_subquery = db.query(
            Comment.post_id,
            func.count(Comment.id).label('count')
        ).filter(
            Comment.post_id.in_(post_ids),
            Comment.deleted_at.is_(None)
        ).group_by(Comment.post_id).all()
        
        for post_id, count in comments_subquery:
            comments_counts[post_id] = count
    
    # Batch loading проверки лайков пользователя (один запрос для всех постов)
    user_liked_posts = set()
    if current_user and post_ids:
        user_likes = db.query(Like.post_id).filter(
            Like.user_id == current_user.id,
            Like.post_id.in_(post_ids)
        ).all()
        user_liked_posts = {like[0] for like in user_likes}
    
    # Batch loading просмотров (один запрос для всех постов)
    views_counts = {}
    if post_ids:
        views_subquery = db.query(
            PostView.post_id,
            func.count(PostView.id).label('count')
        ).filter(
            PostView.post_id.in_(post_ids)
        ).group_by(PostView.post_id).all()
        
        for post_id, count in views_subquery:
            views_counts[post_id] = count
    
    from app.services.post_poll_service import enrich_posts_poll_batch

    poll_bodies = enrich_posts_poll_batch(
        db, posts, current_user.id if current_user else None
    )
    from app.services.post_reaction_service import summarize_post_reactions

    reactions_by_post = summarize_post_reactions(
        db, post_ids, current_user.id if current_user else None
    )

    # Формируем ответ
    posts_data = []
    for post in posts:
        likes_count = likes_counts.get(post.id, 0)
        comments_count = comments_counts.get(post.id, 0)
        views_count = views_counts.get(post.id, 0) or (post.views_count if hasattr(post, 'views_count') else 0)
        is_liked = post.id in user_liked_posts
        
        post_response = PostResponse.model_validate(post).model_dump()
        if post_response.get("channel") is None:
            post_response["channel"] = {
                "id": channel.id,
                "name": channel.name,
                "slug": channel.slug,
                "avatar_url": channel.avatar_url,
                "description": channel.description,
            }
        if post.id in poll_bodies:
            post_response["body"] = poll_bodies[post.id]
        posts_data.append({
            **post_response,
            "likes_count": likes_count,
            "comments_count": comments_count,
            "views_count": views_count,
            "is_liked": is_liked,
            "reactions": reactions_by_post.get(post.id, []),
        })
    
    # total уже вычислен выше
    
    result = {
        "posts": posts_data,
        "total": total,
    }
    
    # Сохраняем в кэш на 5 минут (300 секунд) - только для первой страницы
    if offset == 0:
        try:
            redis_client.setex(cache_key, 300, json.dumps(result, ensure_ascii=False, default=str))
            logger.info(f"💾 Сохранено в кэш: {cache_key}")
        except (RedisConnectionError, RedisTimeoutError) as e:
            logger.warning(f"Redis недоступен для сохранения кэша: {e}")
        except Exception as e:
            logger.warning(f"Ошибка сохранения кэша: {e}")
    
    return result


@router.get("/{channel_id}/members")
async def get_channel_members(
    channel_id: int,
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user)
):
    """Получить список участников канала"""
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Channel not found"
        )
    
    _require_can_view_posts(db, channel, current_user)

    # Получаем участников
    members = db.query(ChannelMember, User).join(
        User, ChannelMember.user_id == User.id
    ).filter(
        ChannelMember.channel_id == channel_id,
        ChannelMember.status == MEMBER_STATUS_ACTIVE,
    ).order_by(
        ChannelMember.role.desc(),  # Админы и модераторы первыми
        ChannelMember.joined_at.asc()
    ).limit(limit).offset(offset).all()
    
    total = db.query(func.count(ChannelMember.id)).filter(
        ChannelMember.channel_id == channel_id,
        ChannelMember.status == MEMBER_STATUS_ACTIVE,
    ).scalar() or 0
    
    members_data = []
    for member, user in members:
        members_data.append({
            "user_id": user.id,
            "username": user.username,
            "name": user.name,
            "avatar_url": user.avatar_url,
            "role": member.role,
            "joined_at": member.joined_at.isoformat() if member.joined_at else None,
        })
    
    return {
        "members": members_data,
        "total": total,
    }


@router.post("/{channel_id}/recipe", status_code=status.HTTP_410_GONE)
async def create_channel_recipe_retired(channel_id: int):
    """Channel recipe create retired — HanWe is a messenger."""
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail={
            "detail": "Kitchen features were removed. HanWe is a messenger.",
            "code": "kitchen_retired",
        },
    )



@router.post("/{channel_id}/post", response_model=PostResponse, status_code=status.HTTP_201_CREATED)
async def create_channel_post(
    channel_id: int,
    request: CreatePostRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """
    Создать обычный пост в канале (текст, изображения, видео)
    
    Типы постов:
    - text: текстовый пост
    - photo: пост с изображениями
    - reel: короткое видео (автоматически отправляется в Рилсы)
    """
    from datetime import datetime
    from app.services.moderation_service import ModerationService
    
    # Проверяем существование канала
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Channel not found"
        )
    
    _require_channel_permission(
        db,
        channel,
        current_user,
        "create_posts",
        "Недостаточно прав для публикации постов в канале",
    )
    
    if request.type == "recipe":
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail={
                "detail": "Kitchen features were removed. HanWe is a messenger.",
                "code": "kitchen_retired",
            },
        )
    
    # Формируем body для поста
    body = {}
    
    # Добавляем медиа, если есть
    if request.media:
        body["media"] = [{"type": item.type, "url": item.url} for item in request.media]
    
    publish_to = [f"channel:{channel_id}"]
    if channel.auto_publish_to_feed:
        publish_to.insert(0, "feed")
    publish_to_reels = request.publish_to_reels
    if publish_to_reels is None:
        publish_to_reels = channel.auto_publish_reels
    if request.type == "reel" and publish_to_reels:
        publish_to.append("reels")
    
    post = Post(
        user_id=current_user.id,
        channel_id=channel_id,
        type=request.type,
        title=request.title,
        description=request.description,
        body=body if body else None,
        publish_to=publish_to,
        visibility="public",
        tags=request.tags or [],
    )

    db.add(post)
    channel.posts_count = (channel.posts_count or 0) + 1
    db.flush()

    from app.services.moderation_apply import run_post_moderation, raise_if_post_rejected
    from app.services.post_publish_service import (
        defer_post_if_scheduled,
        require_creator_for_schedule,
    )

    require_creator_for_schedule(db, current_user, request.scheduled_publish_at)

    scores = run_post_moderation(db, post, current_user)
    raise_if_post_rejected(db, post, scores)

    defer_post_if_scheduled(post, request.scheduled_publish_at)

    db.commit()
    db.refresh(post)
    invalidate_channel_posts_cache(channel_id)

    try:
        from app.services.user_stats_cache import invalidate_user_stats_cache

        invalidate_user_stats_cache([current_user.id])
    except Exception as e:
        logger.warning("Failed to invalidate user stats after channel post: %s", e)

    if post.status == "published":
        try:
            from app.services.feed_service import FeedService
            from app.core.redis_client import get_redis
            redis_client = get_redis()
            feed_service = FeedService(db=db, redis_client=redis_client)

            channel_members = db.query(ChannelMember.user_id).filter(
                ChannelMember.channel_id == channel_id,
                ChannelMember.status == MEMBER_STATUS_ACTIVE,
            ).all()

            for member_user_id, in channel_members:
                feed_service.invalidate_feed_cache(member_user_id)
                logger.info(f"Invalidated feed cache for user {member_user_id} after channel post creation")
        except Exception as e:
            logger.warning(f"Failed to invalidate feed cache: {e}")

    if post.status == "published":
        from app.services.channel_notification_service import send_channel_post_notification
        try:
            send_channel_post_notification(
                db=db,
                channel_id=channel_id,
                post_id=post.id,
                post_type=request.type,
                post_title=request.title,
                author_id=current_user.id
            )
        except Exception as e:
            print(f"⚠️ Error sending channel notifications: {e}")

    return PostResponse.model_validate(post)


@router.put("/{channel_id}/posts/{post_id}", response_model=PostResponse)
async def update_channel_post(
    channel_id: int,
    post_id: int,
    request: UpdatePostRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Обновить пост в канале"""
    # Проверяем существование канала
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Channel not found"
        )
    
    # Проверяем существование поста
    post = db.query(Post).filter(
        Post.id == post_id,
        Post.channel_id == channel_id,
        Post.deleted_at.is_(None)
    ).first()
    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found"
        )
    
    is_author = post.user_id == current_user.id
    if not is_author:
        _require_channel_permission(
            db,
            channel,
            current_user,
            "edit_any_post",
            "Недостаточно прав для редактирования чужих постов канала",
        )
    
    # Обновляем поля поста
    if request.title is not None:
        post.title = request.title
    if request.description is not None:
        post.description = request.description
    if request.tags is not None:
        post.tags = request.tags
    
    if request.visibility is not None and post.type != "recipe":
        post.visibility = request.visibility

    # Обновляем медиа
    if request.media is not None:
        body = post.body or {}
        body["media"] = [media.model_dump() for media in request.media]
        post.body = body

    # Обновляем ссылку (link-пост)
    if post.type == "link" and request.link is not None:
        from app.services.link_preview_service import build_link_body

        try:
            link_body = build_link_body(request.link.url, request.link.preview)
        except ValueError as e:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(e),
            )
        body = post.body or {}
        body.update(link_body)
        post.body = body

    if post.type == "poll" and request.poll is not None:
        from app.services.post_poll_service import update_poll_in_post

        try:
            update_poll_in_post(
                db, post, request.poll.question, request.poll.options
            )
        except ValueError as e:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(e),
            )
    
    db.commit()
    db.refresh(post)
    invalidate_channel_posts_cache(channel_id)

    # Инвалидируем кэш ленты
    if post.status == "published":
        try:
            from app.services.feed_service import FeedService
            from app.core.redis_client import get_redis
            redis_client = get_redis()
            feed_service = FeedService(db=db, redis_client=redis_client)
            
            # Получаем всех подписчиков канала
            channel_members = db.query(ChannelMember.user_id).filter(
                ChannelMember.channel_id == channel_id,
                ChannelMember.status == MEMBER_STATUS_ACTIVE,
            ).all()
            
            # Инвалидируем кэш для каждого подписчика
            for member_user_id, in channel_members:
                feed_service.invalidate_feed_cache(member_user_id)
        except Exception as e:
            logger.warning(f"Failed to invalidate feed cache: {e}")
    
    return PostResponse.model_validate(post)


@router.delete("/{channel_id}/posts/{post_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_channel_post(
    channel_id: int,
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Удалить пост из канала"""
    # Проверяем существование канала
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Channel not found"
        )
    
    # Проверяем существование поста
    post = db.query(Post).filter(
        Post.id == post_id,
        Post.channel_id == channel_id,
        Post.deleted_at.is_(None)
    ).first()
    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found"
        )
    
    is_author = post.user_id == current_user.id
    if not is_author:
        _require_channel_permission(
            db,
            channel,
            current_user,
            "delete_any_post",
            "Недостаточно прав для удаления чужих постов канала",
        )
    
    # Мягкое удаление
    from datetime import datetime
    post.deleted_at = datetime.utcnow()
    
    # Обновляем счетчик постов канала
    if channel.posts_count and channel.posts_count > 0:
        channel.posts_count -= 1
    
    db.commit()
    invalidate_channel_posts_cache(channel_id)
    
    # Инвалидируем кэш ленты
    try:
        from app.services.feed_service import FeedService
        from app.core.redis_client import get_redis
        redis_client = get_redis()
        feed_service = FeedService(db=db, redis_client=redis_client)
        
        # Получаем всех подписчиков канала
        channel_members = db.query(ChannelMember.user_id).filter(
            ChannelMember.channel_id == channel_id,
            ChannelMember.status == MEMBER_STATUS_ACTIVE,
        ).all()
        
        # Инвалидируем кэш для каждого подписчика
        for member_user_id, in channel_members:
            feed_service.invalidate_feed_cache(member_user_id)
    except Exception as e:
        logger.warning(f"Failed to invalidate feed cache: {e}")
    
    return None


@router.get("/feed")
async def get_channels_feed(
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    channel_id: Optional[int] = Query(None, description="Фильтр по каналу"),
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user)
):
    """
    Получить ленту каналов
    
    Показывает посты из всех каналов, на которые подписан пользователь,
    или все публичные посты, если пользователь не авторизован.
    """
    from app.schemas.post import PostResponse
    from app.models.like import Like
    from app.models.comment import Comment
    
    query = db.query(Post).filter(
        Post.status == "published",
        Post.deleted_at.is_(None)
    )
    
    # Фильтр по каналу
    if channel_id:
        query = query.filter(Post.channel_id == channel_id)
    # Если пользователь авторизован, показываем посты из его каналов
    elif current_user:
        subscribed_channels = active_member_channel_ids_subquery(
            db, current_user.id
        )
        query = query.filter(
            (Post.channel_id.in_(subscribed_channels)) |
            (Post.channel_id.is_(None))  # Посты без канала (личные)
        )
    # Если не авторизован, показываем только публичные посты из публичных каналов
    else:
        public_channels = db.query(Channel.id).filter(Channel.is_public == True).subquery()
        query = query.filter(
            (Post.channel_id.in_(public_channels)) |
            (Post.channel_id.is_(None))
        )
    
    # Сортируем по дате публикации
    posts = query.order_by(Post.published_at.desc()).limit(limit).offset(offset).all()
    
    # Обогащаем метаданными
    posts_data = []
    for post in posts:
        likes_count = db.query(func.count(Like.id)).filter(Like.post_id == post.id).scalar() or 0
        comments_count = db.query(func.count(Comment.id)).filter(
            Comment.post_id == post.id,
            Comment.deleted_at.is_(None)
        ).scalar() or 0
        
        is_liked = False
        if current_user:
            is_liked = db.query(Like).filter(
                Like.user_id == current_user.id,
                Like.post_id == post.id
            ).first() is not None
        
        posts_data.append({
            **PostResponse.model_validate(post).model_dump(),
            "likes_count": likes_count,
            "comments_count": comments_count,
            "is_liked": is_liked,
        })
    
    total = query.count()
    
    return {
        "posts": posts_data,
        "total": total,
    }


@router.get("/{channel_id}/recipes", status_code=status.HTTP_410_GONE)
async def get_channel_recipes_retired(channel_id: int):
    """Channel recipe listing retired — HanWe is a messenger."""
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail={
            "detail": "Kitchen features were removed. HanWe is a messenger.",
            "code": "kitchen_retired",
        },
    )



@router.put("/{channel_id}/members/{user_id}/role", response_model=ChannelMemberResponse)
async def update_member_role(
    channel_id: int,
    user_id: int,
    request: UpdateChannelMemberRoleRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Изменить роль участника канала (только владелец или админ)"""
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Channel not found"
        )
    
    _require_channel_permission(
        db,
        channel,
        current_user,
        "manage_subscribers",
        "Недостаточно прав для управления ролями подписчиков",
    )
    
    member = db.query(ChannelMember).filter(
        ChannelMember.channel_id == channel_id,
        ChannelMember.user_id == user_id
    ).first()
    
    if not member:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Member not found"
        )
    
    if member.role == "owner" or channel.admin_user_id == user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot change owner role"
        )
    
    if request.role not in ["admin", "moderator", "member"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid role. Must be: admin, moderator, or member"
        )
    
    member.role = request.role
    if request.role in ("admin", "moderator"):
        member.status = MEMBER_STATUS_ACTIVE
    sync_channel_members_count(db, channel_id)
    db.commit()
    db.refresh(member)

    user = db.query(User).filter(User.id == user_id).first()

    return ChannelMemberResponse(
        id=member.id,
        user_id=member.user_id,
        channel_id=member.channel_id,
        role=member.role,
        status=member.status,
        joined_at=member.joined_at,
        user={
            "id": user.id,
            "name": user.name,
            "username": user.username,
            "avatar_url": user.avatar_url,
        } if user else None,
    )


@router.delete("/{channel_id}/members/{user_id}")
async def remove_member(
    channel_id: int,
    user_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Удалить участника из канала (только владелец или админ)"""
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Channel not found"
        )
    
    _require_channel_permission(
        db,
        channel,
        current_user,
        "manage_subscribers",
        "Недостаточно прав для удаления подписчиков",
    )
    
    member = db.query(ChannelMember).filter(
        ChannelMember.channel_id == channel_id,
        ChannelMember.user_id == user_id
    ).first()
    
    if not member:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Member not found"
        )
    
    if member.role == "owner" or channel.admin_user_id == user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot remove channel owner"
        )
    
    db.delete(member)
    sync_channel_members_count(db, channel_id)
    db.commit()

    return {"message": "Member removed successfully"}


@router.delete("/{channel_id}")
async def delete_channel(
    channel_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Удалить канал (только владелец).

    Посты канала помечаются как удалённые; участники удаляются каскадом;
    кэш ленты инвалидируется для всех затронутых пользователей.
    """
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Channel not found"
        )
    
    if channel.admin_user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only channel owner can delete channel"
        )

    member_rows = (
        db.query(ChannelMember.user_id)
        .filter(ChannelMember.channel_id == channel_id)
        .all()
    )
    feed_user_ids = {uid for (uid,) in member_rows if uid is not None}
    feed_user_ids.add(channel.admin_user_id)

    from datetime import datetime as dt_utc

    now = dt_utc.utcnow()
    db.query(Post).filter(
        Post.channel_id == channel_id,
        Post.deleted_at.is_(None),
    ).update({"deleted_at": now}, synchronize_session=False)

    db.delete(channel)
    db.commit()

    try:
        from app.core.redis_client import get_redis
        from app.services.feed_service import FeedService

        redis = get_redis()
        feed_service = FeedService(db=db, redis_client=redis)
        for uid in feed_user_ids:
            feed_service.invalidate_feed_cache(uid)
    except Exception as e:
        logger.warning("Failed to invalidate feed cache after channel delete: %s", e)

    return {"message": "Channel deleted successfully"}

