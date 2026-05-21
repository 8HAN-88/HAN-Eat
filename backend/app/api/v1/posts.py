"""
API endpoints для публикаций
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import Optional
from app.core.database import get_db
from app.api.dependencies import get_current_user_required, get_current_user
from app.models.user import User
from app.models.post import Post
from app.schemas.post import CreatePostRequest, PostResponse, UpdatePostRequest

router = APIRouter()


def _apply_viewer_post_flags(
    db: Session,
    post_id: int,
    response: PostResponse,
    current_user: Optional[User],
) -> PostResponse:
    """Персональные is_liked / is_saved для текущего пользователя."""
    from app.models.like import Like
    from app.models.saved_post import SavedPost

    if current_user is None:
        return response.model_copy(update={"is_liked": False, "is_saved": False})
    liked = (
        db.query(Like)
        .filter(Like.user_id == current_user.id, Like.post_id == post_id)
        .first()
        is not None
    )
    saved = (
        db.query(SavedPost)
        .filter(SavedPost.user_id == current_user.id, SavedPost.post_id == post_id)
        .first()
        is not None
    )
    return response.model_copy(update={"is_liked": liked, "is_saved": saved})


@router.post("/{post_id}/view", status_code=status.HTTP_201_CREATED)
async def mark_post_as_viewed(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Отметить пост как прочитанный (увеличить счетчик просмотров)"""
    from app.models.post_view import PostView
    from datetime import datetime
    
    # Проверяем существование поста
    post = db.query(Post).filter(Post.id == post_id, Post.deleted_at.is_(None)).first()
    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found"
        )
    
    # Проверяем, не просмотрел ли уже пользователь этот пост
    existing_view = db.query(PostView).filter(
        PostView.post_id == post_id,
        PostView.user_id == current_user.id
    ).first()
    
    if not existing_view:
        # Создаем новую запись о просмотре
        post_view = PostView(
            post_id=post_id,
            user_id=current_user.id,
            viewed_at=datetime.utcnow()
        )
        db.add(post_view)
        
        # Увеличиваем счетчик просмотров поста
        post.views_count = (post.views_count or 0) + 1
        db.commit()
    
    return {"message": "Post marked as viewed", "views_count": post.views_count or 0}


@router.post("", response_model=PostResponse, status_code=status.HTTP_201_CREATED)
async def create_post(
    request: CreatePostRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Создать пост"""
    from datetime import datetime
    
    # Формируем body для рецептов
    body = None
    if request.type == "recipe":
        body = {
            "ingredients": request.ingredients or [],
            "steps": [step.model_dump() for step in (request.steps or [])],
            "prep_time_min": request.prep_time_min,
            "cook_time_min": request.cook_time_min,
            "servings": request.servings,
            "calories": request.calories,
        }
    
    # Обрабатываем медиа
    media_items = []
    if request.media:
        for item in request.media:
            media_items.append({
                "type": item.type,
                "url": item.url,
            })
    
    # Сохраняем медиа в поле body или создаем отдельное поле
    # Пока сохраняем в body для гибкости
    if media_items:
        if body is None:
            body = {}
        body["media"] = media_items
    
    post = Post(
        user_id=current_user.id,
        type=request.type,
        title=request.title,
        description=request.description,
        body=body,
        publish_to=request.publish_to or ["feed"],
        visibility=request.visibility or "public",
        tags=request.tags or [],
    )
    
    # Если указан канал
    if request.channel_id:
        from app.models.community import Channel
        from app.models.community_member import ChannelMember
        
        channel = db.query(Channel).filter(Channel.id == request.channel_id).first()
        if not channel:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Channel not found"
            )
        
        # Проверяем, является ли пользователь владельцем, админом или модератором канала
        # Владелец канала (admin_user_id) всегда может публиковать
        is_owner = channel.admin_user_id == current_user.id
        
        if is_owner:
            # Владелец канала всегда может публиковать, пропускаем проверку участников
            pass
        else:
            # Для не-владельцев проверяем роль участника
            member = db.query(ChannelMember).filter(
                ChannelMember.channel_id == request.channel_id,
                ChannelMember.user_id == current_user.id
            ).first()
            
            # Участники с ролями owner, admin или moderator могут публиковать
            is_admin_or_moderator = member and member.role in ["admin", "moderator", "owner"]
            
            if not is_admin_or_moderator:
                # Логируем для отладки
                import logging
                logger = logging.getLogger(__name__)
                logger.warning(
                    f"User {current_user.id} (username: {current_user.username}) tried to post to channel {request.channel_id}. "
                    f"Channel owner: {channel.admin_user_id}, Is owner: {is_owner}, "
                    f"Member found: {member is not None}, Member role: {member.role if member else 'None'}"
                )
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=f"Only channel owner, admins and moderators can post to channel. "
                           f"Channel owner ID: {channel.admin_user_id}, Your ID: {current_user.id}"
                )
        
        post.channel_id = request.channel_id
        # Обновляем счетчик постов канала
        channel.posts_count = (channel.posts_count or 0) + 1
    
    from app.services.anti_spam_service import AntiSpamService
    from app.services.moderation_apply import run_post_moderation
    from datetime import datetime

    ok, spam_msg = AntiSpamService(db).check_can_create_post(current_user)
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=spam_msg or "Rate limit exceeded",
        )

    db.add(post)
    db.flush()

    from app.services.moderation_apply import raise_if_post_rejected

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

    # Загружаем пользователя для включения в ответ (eager loading)
    from sqlalchemy.orm import joinedload
    post_with_user = db.query(Post).options(joinedload(Post.user)).filter(Post.id == post.id).first()
    if post_with_user:
        post = post_with_user
    
    # Инвалидируем кэш фида для подписчиков автора (если пост опубликован)
    if post.status == "published":
        try:
            from app.core.redis_client import get_redis
            from app.models.follower import Follower
            from app.services.feed_service import FeedService
            
            redis_client = get_redis()
            feed_service = FeedService(db, redis_client)
            
            # Получаем всех подписчиков автора
            followers = db.query(Follower.follower_id).filter(
                Follower.followee_id == current_user.id
            ).all()
            follower_ids = [row[0] for row in followers]
            
            # Инвалидируем кэш для всех подписчиков
            for follower_id in follower_ids:
                feed_service.invalidate_feed_cache(follower_id)
            
            # Также инвалидируем кэш для самого автора
            feed_service.invalidate_feed_cache(current_user.id)
            
        except Exception as e:
            # Не критично, если не удалось инвалидировать кэш
            import logging
            logger = logging.getLogger(__name__)
            logger.warning(f"Failed to invalidate feed cache after post creation: {e}")
    
    return PostResponse.model_validate(post)


@router.get("/{post_id}", response_model=PostResponse)
async def get_post(
    post_id: int,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user)
):
    """Получить пост"""
    # Пытаемся получить из кэша (для популярных постов)
    from app.core.redis_client import get_redis
    import json
    redis_client = get_redis()
    cache_key = f"post:{post_id}"
    
    try:
        cached_post = redis_client.get(cache_key)
        if cached_post:
            post_data = json.loads(cached_post)
            # Проверяем видимость
            if post_data.get("visibility") == "private" and (not current_user or current_user.id != post_data.get("user_id")):
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Post is private"
                )
            # Логируем просмотр (асинхронно, не блокируем ответ)
            if current_user:
                from app.services.analytics_service import AnalyticsService
                analytics_service = AnalyticsService(db)
                analytics_service.log_event(
                    event_type="view",
                    entity_type="post",
                    entity_id=post_id,
                    user_id=current_user.id,
                    author_id=post_data.get("user_id"),
                )
                db.commit()
            pr = PostResponse(**post_data)
            return _apply_viewer_post_flags(db, post_id, pr, current_user)
    except HTTPException:
        raise
    except Exception:
        # Если кэш не работает, продолжаем обычным способом
        pass
    
    # Загружаем пост с eager loading (оптимизация для 100k пользователей)
    from sqlalchemy.orm import joinedload, selectinload
    post = db.query(Post).options(
        joinedload(Post.user),
        selectinload(Post.channel)
    ).filter(
        Post.id == post_id,
        Post.deleted_at.is_(None)
    ).first()
    
    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found"
        )
    
    # Проверяем видимость
    if post.visibility == "private" and (not current_user or current_user.id != post.user_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Post is private"
        )
    
    # Логируем просмотр поста
    if current_user:
        from app.services.analytics_service import AnalyticsService
        analytics_service = AnalyticsService(db)
        analytics_service.log_event(
            event_type="view",
            entity_type="post",
            entity_id=post_id,
            user_id=current_user.id,
            author_id=post.user_id,
        )
        db.commit()
    
    # Кэшируем популярные посты (с лайками > 10) на 10 минут
    try:
        if post.likes_count and post.likes_count > 10:
            post_dict = PostResponse.model_validate(post).model_dump()
            redis_client.setex(
                cache_key,
                600,  # 10 минут
                json.dumps(post_dict, default=str)
            )
    except Exception:
        # Не критично, если кэширование не сработало
        pass
    
    pr = PostResponse.model_validate(post)
    return _apply_viewer_post_flags(db, post_id, pr, current_user)

