"""
API endpoints для каналов
"""
import json
import logging
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import func
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
from app.schemas.channel import (
    CreateChannelRequest,
    UpdateChannelRequest,
    ChannelResponse,
    ChannelDetailResponse,
    JoinChannelResponse,
    ChannelMemberResponse,
    UpdateChannelMemberRoleRequest,
    ChannelNotificationsPatchRequest,
)
from app.schemas.post import CreatePostRequest, UpdatePostRequest, PostResponse, RecipeStep

router = APIRouter()


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
        
        # Создаем канал
        channel = Channel(
            name=request.name,
            slug=request.slug,
            description=request.description,
            cover_url=request.cover_url,
            avatar_url=request.avatar_url,
            admin_user_id=current_user.id,
            is_public=request.is_public if request.is_public is not None else True,
            category=request.category,
            tags=request.tags if request.tags is not None else [],
            members_count=1,  # Админ автоматически становится участником
            posts_count=0,
            auto_publish_to_feed=True,
            auto_publish_to_menu=True,
            allow_comments=True,
            allow_likes=True,
            allow_reposts=True,
            auto_publish_reels=request.auto_publish_reels,
        )
        
        db.add(channel)
        db.commit()
        db.refresh(channel)
        
        # Добавляем владельца как участника с ролью "owner"
        member = ChannelMember(
            channel_id=channel.id,
            user_id=current_user.id,
            role="owner",
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
    
    # Проверяем права доступа
    member = db.query(ChannelMember).filter(
        ChannelMember.channel_id == channel_id,
        ChannelMember.user_id == current_user.id
    ).first()
    
    is_owner = channel.admin_user_id == current_user.id
    is_admin = member and (member.role == "admin" or member.role == "owner")
    
    if not (is_owner or is_admin):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only channel owner or admin can update channel"
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
    if request.is_public is not None:
        channel.is_public = request.is_public
    if request.category is not None:
        channel.category = request.category
    if request.tags is not None:
        channel.tags = request.tags
    if request.rules is not None:
        channel.rules = request.rules
    if request.auto_publish_to_feed is not None:
        channel.auto_publish_to_feed = request.auto_publish_to_feed
    if request.auto_publish_to_menu is not None:
        channel.auto_publish_to_menu = request.auto_publish_to_menu
    if request.allow_comments is not None:
        channel.allow_comments = request.allow_comments
    if request.allow_likes is not None:
        channel.allow_likes = request.allow_likes
    if request.allow_reposts is not None:
        channel.allow_reposts = request.allow_reposts
    if request.auto_publish_reels is not None:
        channel.auto_publish_reels = request.auto_publish_reels
    
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
    
    # Проверяем, является ли пользователь участником и его роль
    is_member = False
    is_admin = False
    is_owner = False
    is_moderator = False
    channel_notifications_enabled = None
    if current_user:
        member = db.query(ChannelMember).filter(
            ChannelMember.channel_id == channel_id,
            ChannelMember.user_id == current_user.id
        ).first()
        if member:
            is_member = True
            is_admin = member.role == "admin"
            is_owner = member.role == "owner" or channel.admin_user_id == current_user.id
            is_moderator = member.role == "moderator"
            channel_notifications_enabled = bool(
                getattr(member, "notifications_enabled", True)
            )
        # Также проверяем, является ли пользователь владельцем через admin_user_id
        if channel.admin_user_id == current_user.id:
            is_owner = True
            is_admin = True
    
    # Информация об админе (уже может быть загружен через relationship, но на всякий случай)
    admin = db.query(User).filter(User.id == channel.admin_user_id).first()
    
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
        auto_publish_to_feed=channel.auto_publish_to_feed if channel.auto_publish_to_feed is not None else True,
        auto_publish_to_menu=channel.auto_publish_to_menu if channel.auto_publish_to_menu is not None else True,
        allow_comments=channel.allow_comments if channel.allow_comments is not None else True,
        allow_likes=channel.allow_likes if channel.allow_likes is not None else True,
        allow_reposts=channel.allow_reposts if channel.allow_reposts is not None else True,
        is_owner=is_owner,
        is_moderator=is_moderator,
        members_count=channel.members_count if channel.members_count is not None else 0,
        posts_count=channel.posts_count if channel.posts_count is not None else 0,
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
    )


@router.get("", response_model=dict)
async def list_channels(
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    search: Optional[str] = Query(None, description="Поиск по названию и описанию"),
    subscribed: Optional[bool] = Query(None, description="Мои каналы (требует авторизации)"),
    recommended: Optional[bool] = Query(None, description="Рекомендованные каналы"),
    catalog: Optional[bool] = Query(None, description="Каталог всех каналов"),
    category: Optional[str] = Query(None, description="Фильтр по категории/тематике"),
    sort: Optional[str] = Query("popular", description="Сортировка: popular, new, members, activity, posts"),
    min_subscribers: Optional[int] = Query(None, description="Минимальное количество подписчиков"),
    max_subscribers: Optional[int] = Query(None, description="Максимальное количество подписчиков"),
    has_recipes: Optional[bool] = Query(None, description="Только каналы с рецептами"),
    min_posts: Optional[int] = Query(None, description="Минимальное количество постов"),
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
    query = db.query(Channel).filter(Channel.is_public == True)
    
    # Мои каналы
    if subscribed and current_user:
        query = query.join(ChannelMember).filter(
            ChannelMember.user_id == current_user.id,
            ChannelMember.channel_id == Channel.id
        )
    # Рекомендованные (улучшенный алгоритм)
    elif recommended:
        if current_user:
            # Исключаем каналы, на которые пользователь уже подписан
            subscribed_channel_ids = db.query(ChannelMember.channel_id).filter(
                ChannelMember.user_id == current_user.id
            ).subquery()
            query = query.filter(~Channel.id.in_(subscribed_channel_ids))
            
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
                Channel.category.isnot(None)
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
            items.append(ChannelResponse.model_validate(ch))
        except Exception as e:
            # Логируем ошибку, но продолжаем обработку других каналов
            import logging
            logger = logging.getLogger(__name__)
            logger.error(f"Error validating channel {ch.id}: {e}", exc_info=True)
            # Пропускаем проблемный канал
            continue
    
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
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Already a member of this channel"
        )
    
    # Добавляем участника
    member = ChannelMember(
        channel_id=channel_id,
        user_id=current_user.id,
        role="member",
    )
    db.add(member)
    
    # Обновляем счетчик
    channel.members_count = (channel.members_count or 0) + 1
    db.commit()
    
    return JoinChannelResponse(
        joined=True,
        members_count=channel.members_count
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
    
    # Админ не может покинуть канал (нужно передать права или удалить канал)
    if member.role == "admin":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Admin cannot leave channel. Transfer admin rights or delete channel."
        )
    
    # Удаляем участника
    db.delete(member)
    
    # Обновляем счетчик
    channel.members_count = max((channel.members_count or 1) - 1, 0)
    db.commit()
    
    return JoinChannelResponse(
        joined=False,
        members_count=channel.members_count
    )


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
    if not member:
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
    cache_key = f"channel_posts:{channel_id}:{post_type or 'all'}:{limit}:{offset}"
    if current_user:
        cache_key += f":user_{current_user.id}"
    
    # Проверяем кэш (только для offset=0, чтобы не кэшировать все страницы)
    if offset == 0:
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
    
    # Проверяем доступ (если канал приватный, нужна подписка)
    if not channel.is_public:
        if not current_user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Authentication required"
            )
        is_member = db.query(ChannelMember).filter(
            ChannelMember.channel_id == channel_id,
            ChannelMember.user_id == current_user.id
        ).first() is not None
        
        if not is_member:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Channel is private"
            )
    
    # Получаем посты с фильтрацией по типу
    query = db.query(Post).filter(
        Post.channel_id == channel_id,
        Post.status == "published",
        Post.deleted_at.is_(None)
    )
    
    # Фильтр по типу поста
    if post_type:
        query = query.filter(Post.type == post_type)
    
    # Для отображения как в чатах Telegram: новые посты внизу, старые вверху
    # Всегда показываем последние посты при offset=0 (как в Telegram)
    # Сортируем по убыванию даты (новые первыми)
    posts = query.order_by(Post.published_at.desc()).limit(limit).offset(offset).all()
    
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
    from sqlalchemy import func
    
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
    
    # Формируем ответ
    posts_data = []
    for post in posts:
        likes_count = likes_counts.get(post.id, 0)
        comments_count = comments_counts.get(post.id, 0)
        views_count = views_counts.get(post.id, 0) or (post.views_count if hasattr(post, 'views_count') else 0)
        is_liked = post.id in user_liked_posts
        
        post_response = PostResponse.model_validate(post).model_dump()
        posts_data.append({
            **post_response,
            "likes_count": likes_count,
            "comments_count": comments_count,
            "views_count": views_count,
            "is_liked": is_liked,
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
    
    # Проверяем доступ (если канал приватный, нужна подписка)
    if not channel.is_public:
        if not current_user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Authentication required"
            )
        is_member = db.query(ChannelMember).filter(
            ChannelMember.channel_id == channel_id,
            ChannelMember.user_id == current_user.id
        ).first() is not None
        
        if not is_member:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Channel is private"
            )
    
    # Получаем участников
    members = db.query(ChannelMember, User).join(
        User, ChannelMember.user_id == User.id
    ).filter(
        ChannelMember.channel_id == channel_id
    ).order_by(
        ChannelMember.role.desc(),  # Админы и модераторы первыми
        ChannelMember.joined_at.asc()
    ).limit(limit).offset(offset).all()
    
    total = db.query(func.count(ChannelMember.id)).filter(
        ChannelMember.channel_id == channel_id
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


@router.post("/{channel_id}/recipe", response_model=PostResponse, status_code=status.HTTP_201_CREATED)
async def create_channel_recipe(
    channel_id: int,
    request: CreatePostRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """
    Создать рецепт в канале
    
    При публикации рецепта в канале:
    1. Сохраняется в posts с type='recipe' и channel_id
    2. Автоматически участвует в поиске по ингредиентам (Menu)
    3. Отображается в ленте каналов
    4. Отображается в Menu
    """
    from datetime import datetime
    from app.services.moderation_service import ModerationService
    # Используем глобальный logger из начала файла
    
    # Проверяем существование канала
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Channel not found"
        )
    
    # Проверяем, является ли пользователь владельцем, админом или модератором канала
    is_owner = channel.admin_user_id == current_user.id
    
    if is_owner:
        # Владелец канала всегда может публиковать
        pass
    else:
        # Для не-владельцев проверяем роль участника
        member = db.query(ChannelMember).filter(
            ChannelMember.channel_id == channel_id,
            ChannelMember.user_id == current_user.id
        ).first()
        
        # Участники с ролями owner, admin или moderator могут публиковать
        is_admin_or_moderator = member and member.role in ["admin", "moderator", "owner"]
        
        if not is_admin_or_moderator:
            # Используем глобальный logger из начала файла
            logger.warning(
                f"User {current_user.id} (username: {current_user.username}) tried to post recipe to channel {channel_id}. "
                f"Channel owner: {channel.admin_user_id}, Is owner: {is_owner}, "
                f"Member found: {member is not None}, Member role: {member.role if member else 'None'}"
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Only channel owner, admins and moderators can post recipes to channel. "
                       f"Channel owner ID: {channel.admin_user_id}, Your ID: {current_user.id}"
            )
    
    # Валидация: должен быть тип recipe
    if request.type != "recipe":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This endpoint is only for creating recipes. Use /posts for other types."
        )

    # Рецепт без названия публиковать нельзя
    if not (request.title or "").strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Название рецепта обязательно"
        )
    
    # Формируем body для рецепта
    steps_data = []
    for step in (request.steps or []):
        step_dict = step.model_dump(exclude_none=True)
        # Убеждаемся, что изображения сохраняются
        # Проверяем оба поля и сохраняем оба для совместимости
        if step.image:
            step_dict['image'] = step.image
            step_dict['image_url'] = step.image  # Дублируем для совместимости
        elif step.image_url:
            step_dict['image'] = step.image_url  # Дублируем для совместимости
            step_dict['image_url'] = step.image_url
        steps_data.append(step_dict)
        logger.info(f"Шаг {step.number}: текст={step.text[:50]}..., изображение={step.image or step.image_url or 'нет'}")
        logger.info(f"Шаг {step.number} step_dict: {step_dict}")
    
    body = {
        "ingredients": request.ingredients or [],
        "steps": steps_data,
        "prep_time_min": request.prep_time_min,
        "cook_time_min": request.cook_time_min,
        "servings": request.servings,
        "calories": request.calories,
    }
    # Денормализация для карточек «Меню» / клиентов, читающих только body
    if channel.name:
        body["channel_name"] = channel.name
    ch_img = (channel.avatar_url or channel.cover_url or "").strip()
    if ch_img:
        body["channel_avatar"] = ch_img
    
    # Добавляем медиа, если есть
    if request.media:
        body["media"] = [{"type": item.type, "url": item.url} for item in request.media]
    
    # Логируем финальный body для отладки
    logger.info(f"Создаем пост с body: {body}")
    import json
    logger.info(f"Body JSON: {json.dumps(body, ensure_ascii=False, indent=2)}")
    
    post = Post(
        user_id=current_user.id,
        channel_id=channel_id,
        type="recipe",
        title=request.title,
        description=request.description,
        body=body,
        publish_to=["feed", f"channel:{channel_id}"],
        visibility="public",
        tags=request.tags or [],
    )

    db.add(post)
    channel.posts_count = (channel.posts_count or 0) + 1
    db.flush()

    from app.services.moderation_apply import run_post_moderation, raise_if_post_rejected

    scores = run_post_moderation(db, post, current_user)
    raise_if_post_rejected(db, post, scores)

    db.commit()
    db.refresh(post)
    
    # Инвалидируем кэш ленты для всех подписчиков канала
    if post.status == "published":
        try:
            from app.services.feed_service import FeedService
            from app.core.redis_client import get_redis
            redis_client = get_redis()
            feed_service = FeedService(db=db, redis_client=redis_client)
            
            # Получаем всех подписчиков канала
            channel_members = db.query(ChannelMember.user_id).filter(
                ChannelMember.channel_id == channel_id
            ).all()
            
            # Инвалидируем кэш для каждого подписчика
            for member_user_id, in channel_members:
                feed_service.invalidate_feed_cache(member_user_id)
                logger.info(f"Invalidated feed cache for user {member_user_id} after channel post creation")
        except Exception as e:
            logger.warning(f"Failed to invalidate feed cache: {e}")
    
    # Отправляем уведомления подписчикам канала о новом рецепте
    if post.status == "published":
        from app.services.channel_notification_service import send_channel_post_notification
        try:
            send_channel_post_notification(
                db=db,
                channel_id=channel_id,
                post_id=post.id,
                post_type="recipe",
                post_title=request.title,
                author_id=current_user.id
            )
        except Exception as e:
            print(f"⚠️ Error sending channel notifications: {e}")
    
    return PostResponse.model_validate(post)


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
    
    # Проверяем, является ли пользователь владельцем, админом или модератором канала
    is_owner = channel.admin_user_id == current_user.id
    
    if is_owner:
        # Владелец канала всегда может публиковать
        pass
    else:
        # Для не-владельцев проверяем роль участника
        member = db.query(ChannelMember).filter(
            ChannelMember.channel_id == channel_id,
            ChannelMember.user_id == current_user.id
        ).first()
        
        # Участники с ролями owner, admin или moderator могут публиковать
        is_admin_or_moderator = member and member.role in ["admin", "moderator", "owner"]
        
        if not is_admin_or_moderator:
            # Используем глобальный logger из начала файла
            logger.warning(
                f"User {current_user.id} (username: {current_user.username}) tried to post to channel {channel_id}. "
                f"Channel owner: {channel.admin_user_id}, Is owner: {is_owner}, "
                f"Member found: {member is not None}, Member role: {member.role if member else 'None'}"
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Only channel owner, admins and moderators can post to channel. "
                       f"Channel owner ID: {channel.admin_user_id}, Your ID: {current_user.id}"
            )
    
    # Валидация: не должен быть тип recipe (для рецептов используется отдельный эндпоинт)
    if request.type == "recipe":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Use /recipe endpoint for creating recipes"
        )
    
    # Формируем body для поста
    body = {}
    
    # Добавляем медиа, если есть
    if request.media:
        body["media"] = [{"type": item.type, "url": item.url} for item in request.media]
    
    # Для рилсов автоматически добавляем в publish_to
    publish_to = ["feed", f"channel:{channel_id}"]
    publish_to_reels = request.publish_to_reels
    if publish_to_reels is None:
        publish_to_reels = channel.auto_publish_reels
    if request.type == "reel" and publish_to_reels:
        publish_to.append("reels")  # Автоматически в Рилсы
    
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

    if post.status == "published":
        try:
            from app.services.feed_service import FeedService
            from app.core.redis_client import get_redis
            redis_client = get_redis()
            feed_service = FeedService(db=db, redis_client=redis_client)

            channel_members = db.query(ChannelMember.user_id).filter(
                ChannelMember.channel_id == channel_id
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
    
    # Проверяем права: только автор поста, владелец канала, админ или модератор могут редактировать
    is_owner = channel.admin_user_id == current_user.id
    is_author = post.user_id == current_user.id
    
    if not (is_owner or is_author):
        # Проверяем роль участника
        member = db.query(ChannelMember).filter(
            ChannelMember.channel_id == channel_id,
            ChannelMember.user_id == current_user.id
        ).first()
        
        is_admin_or_moderator = member and member.role in ["admin", "moderator", "owner"]
        
        if not is_admin_or_moderator:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only post author, channel owner, admins and moderators can edit posts"
            )
    
    # Обновляем поля поста
    if request.title is not None:
        post.title = request.title
    if request.description is not None:
        post.description = request.description
    if request.tags is not None:
        post.tags = request.tags
    
    # Обновляем body для рецептов
    if post.type == "recipe":
        body = post.body or {}
        
        if request.ingredients is not None:
            body["ingredients"] = request.ingredients
        if request.steps is not None:
            body["steps"] = [step.model_dump() for step in request.steps]
        if request.prep_time_min is not None:
            body["prep_time_min"] = request.prep_time_min
        if request.cook_time_min is not None:
            body["cook_time_min"] = request.cook_time_min
        if request.servings is not None:
            body["servings"] = request.servings
        if request.calories is not None:
            body["calories"] = request.calories
        
        post.body = body
    
    # Обновляем медиа
    if request.media is not None:
        body = post.body or {}
        body["media"] = [media.model_dump() for media in request.media]
        post.body = body
    
    db.commit()
    db.refresh(post)
    
    # Инвалидируем кэш ленты
    if post.status == "published":
        try:
            from app.services.feed_service import FeedService
            from app.core.redis_client import get_redis
            redis_client = get_redis()
            feed_service = FeedService(db=db, redis_client=redis_client)
            
            # Получаем всех подписчиков канала
            channel_members = db.query(ChannelMember.user_id).filter(
                ChannelMember.channel_id == channel_id
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
    
    # Проверяем права: только автор поста, владелец канала, админ или модератор могут удалять
    is_owner = channel.admin_user_id == current_user.id
    is_author = post.user_id == current_user.id
    
    if not (is_owner or is_author):
        # Проверяем роль участника
        member = db.query(ChannelMember).filter(
            ChannelMember.channel_id == channel_id,
            ChannelMember.user_id == current_user.id
        ).first()
        
        is_admin_or_moderator = member and member.role in ["admin", "moderator", "owner"]
        
        if not is_admin_or_moderator:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only post author, channel owner, admins and moderators can delete posts"
            )
    
    # Мягкое удаление
    from datetime import datetime
    post.deleted_at = datetime.utcnow()
    
    # Обновляем счетчик постов канала
    if channel.posts_count and channel.posts_count > 0:
        channel.posts_count -= 1
    
    db.commit()
    
    # Инвалидируем кэш ленты
    try:
        from app.services.feed_service import FeedService
        from app.core.redis_client import get_redis
        redis_client = get_redis()
        feed_service = FeedService(db=db, redis_client=redis_client)
        
        # Получаем всех подписчиков канала
        channel_members = db.query(ChannelMember.user_id).filter(
            ChannelMember.channel_id == channel_id
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
        subscribed_channels = db.query(ChannelMember.channel_id).filter(
            ChannelMember.user_id == current_user.id
        ).subquery()
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


@router.get("/{channel_id}/recipes")
async def get_channel_recipes(
    channel_id: int,
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user)
):
    """Получить только рецепты канала"""
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Channel not found"
        )
    
    if not channel.is_public:
        if not current_user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Authentication required"
            )
        is_member = db.query(ChannelMember).filter(
            ChannelMember.channel_id == channel_id,
            ChannelMember.user_id == current_user.id
        ).first() is not None
        if not is_member:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Channel is private"
            )
    
    from app.models.like import Like
    from app.models.comment import Comment
    from app.schemas.post import PostResponse
    
    posts = db.query(Post).filter(
        Post.channel_id == channel_id,
        Post.type == "recipe",
        Post.status == "published",
        Post.deleted_at.is_(None)
    ).order_by(Post.published_at.desc()).limit(limit).offset(offset).all()
    
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
    
    total = db.query(func.count(Post.id)).filter(
        Post.channel_id == channel_id,
        Post.type == "recipe",
        Post.status == "published",
        Post.deleted_at.is_(None)
    ).scalar() or 0
    
    return {
        "posts": posts_data,
        "total": total,
    }


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
    
    is_owner = channel.admin_user_id == current_user.id
    current_member = db.query(ChannelMember).filter(
        ChannelMember.channel_id == channel_id,
        ChannelMember.user_id == current_user.id
    ).first()
    is_admin = current_member and (current_member.role == "admin" or current_member.role == "owner")
    
    if not (is_owner or is_admin):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only channel owner or admin can change member roles"
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
    db.commit()
    db.refresh(member)
    
    user = db.query(User).filter(User.id == user_id).first()
    
    return ChannelMemberResponse(
        id=member.id,
        user_id=member.user_id,
        channel_id=member.channel_id,
        role=member.role,
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
    
    is_owner = channel.admin_user_id == current_user.id
    current_member = db.query(ChannelMember).filter(
        ChannelMember.channel_id == channel_id,
        ChannelMember.user_id == current_user.id
    ).first()
    is_admin = current_member and (current_member.role == "admin" or current_member.role == "owner")
    
    if not (is_owner or is_admin):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only channel owner or admin can remove members"
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
    
    channel.members_count = max(0, channel.members_count - 1)
    
    db.delete(member)
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

