"""
API endpoints для лайков
"""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from sqlalchemy import func
from app.core.database import get_db
from app.api.dependencies import get_current_user_required
from app.models.user import User
from app.models.post import Post
from app.models.like import Like

router = APIRouter()


@router.post("/posts/{post_id}/like", status_code=status.HTTP_201_CREATED)
async def like_post(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Лайкнуть пост"""
    # Проверяем, что пост существует
    post = db.query(Post).filter(
        Post.id == post_id,
        Post.deleted_at.is_(None)
    ).first()
    
    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found"
        )
    
    # Проверяем, не лайкнул ли уже
    existing_like = db.query(Like).filter(
        Like.user_id == current_user.id,
        Like.post_id == post_id
    ).first()
    
    if existing_like:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Post already liked"
        )
    
    # Создаем лайк
    like = Like(
        user_id=current_user.id,
        post_id=post_id,
    )
    
    db.add(like)
    
    # Логируем событие
    from app.services.analytics_service import AnalyticsService
    analytics_service = AnalyticsService(db)
    analytics_service.log_event(
        event_type="like",
        entity_type="post",
        entity_id=post_id,
        user_id=current_user.id,
        author_id=post.user_id,
    )
    
    # Отправляем уведомление автору поста
    from app.services.notification_service import NotificationService
    notification_service = NotificationService(db)
    notification_service.notify_like(
        post_author_id=post.user_id,
        liker_id=current_user.id,
        post_id=post_id,
        liker_name=current_user.name
    )
    
    db.commit()
    try:
        from app.core.redis_client import get_redis
        from app.services.feed_service import FeedService

        FeedService(db, get_redis()).invalidate_feed_cache(current_user.id)
    except Exception:
        pass
    
    # Получаем количество лайков
    likes_count = db.query(func.count(Like.id)).filter(
        Like.post_id == post_id
    ).scalar() or 0
    
    return {
        "liked": True,
        "likes_count": likes_count
    }


@router.delete("/posts/{post_id}/like", status_code=status.HTTP_200_OK)
async def unlike_post(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Убрать лайк с поста"""
    # Находим лайк
    like = db.query(Like).filter(
        Like.user_id == current_user.id,
        Like.post_id == post_id
    ).first()
    
    if not like:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Like not found"
        )
    
    db.delete(like)
    db.commit()
    try:
        from app.core.redis_client import get_redis
        from app.services.feed_service import FeedService

        FeedService(db, get_redis()).invalidate_feed_cache(current_user.id)
    except Exception:
        pass
    
    # Получаем количество лайков
    likes_count = db.query(func.count(Like.id)).filter(
        Like.post_id == post_id
    ).scalar() or 0
    
    return {
        "liked": False,
        "likes_count": likes_count
    }


@router.get("/posts/{post_id}/like/status")
async def get_like_status(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Проверить, лайкнул ли пользователь пост"""
    like = db.query(Like).filter(
        Like.user_id == current_user.id,
        Like.post_id == post_id
    ).first()
    
    # Получаем количество лайков
    likes_count = db.query(func.count(Like.id)).filter(
        Like.post_id == post_id
    ).scalar() or 0
    
    return {
        "liked": like is not None,
        "likes_count": likes_count
    }


@router.get("/posts/{post_id}/likes")
async def list_post_likes(
    post_id: int,
    limit: int = Query(40, ge=1, le=100),
    cursor: Optional[int] = Query(None, description="Like id cursor (exclusive)"),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Список пользователей, которым понравился пост."""
    post = (
        db.query(Post.id)
        .filter(Post.id == post_id, Post.deleted_at.is_(None))
        .first()
    )
    if not post:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Post not found")

    total = (
        db.query(func.count(Like.id)).filter(Like.post_id == post_id).scalar()
        or 0
    )
    q = (
        db.query(Like, User)
        .join(User, User.id == Like.user_id)
        .filter(Like.post_id == post_id)
    )
    if cursor is not None and int(cursor) > 0:
        q = q.filter(Like.id < int(cursor))
    rows = q.order_by(Like.id.desc()).limit(limit).all()
    items = [
        {
            "like_id": int(like.id),
            "id": int(user.id),
            "name": user.name or "Пользователь",
            "username": user.username,
            "avatar_url": user.avatar_url,
        }
        for like, user in rows
    ]
    next_cursor = items[-1]["like_id"] if len(items) >= limit else None
    return {
        "items": items,
        "total": int(total),
        "next_cursor": next_cursor,
    }

