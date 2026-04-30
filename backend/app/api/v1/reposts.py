"""
API endpoints для репостов
"""
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import Optional
from pydantic import BaseModel
from app.core.database import get_db
from app.api.dependencies import get_current_user_required, get_current_user
from app.models.user import User
from app.models.post import Post
from app.models.repost import Repost
from app.models.like import Like
from app.models.comment import Comment
from app.schemas.post import PostResponse

router = APIRouter()


class CreateRepostRequest(BaseModel):
    comment: Optional[str] = None  # Комментарий к репосту


@router.post("/posts/{post_id}/repost", status_code=status.HTTP_201_CREATED)
async def create_repost(
    post_id: int,
    request: CreateRepostRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Создать репост"""
    # Проверяем, существует ли пост
    post = db.query(Post).filter(
        Post.id == post_id,
        Post.deleted_at.is_(None)
    ).first()
    
    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found"
        )
    
    # Проверяем, не репостнул ли уже
    existing = db.query(Repost).filter(
        Repost.user_id == current_user.id,
        Repost.post_id == post_id
    ).first()
    
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Post already reposted"
        )
    
    # Нельзя репостнуть свой пост из профиля (но можно из канала на профиль)
    if post.user_id == current_user.id and post.channel_id is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot repost your own post"
        )
    
    # Создаем репост
    repost = Repost(
        user_id=current_user.id,
        post_id=post_id,
        comment=request.comment,
    )
    
    db.add(repost)
    
    # Логируем событие
    from app.services.analytics_service import AnalyticsService
    analytics_service = AnalyticsService(db)
    analytics_service.log_event(
        event_type="repost",
        entity_type="post",
        entity_id=post_id,
        user_id=current_user.id,
        author_id=post.user_id,
    )
    
    # Отправляем уведомление автору поста
    from app.services.notification_service import NotificationService
    notification_service = NotificationService(db)
    notification_service.notify_repost(
        post_author_id=post.user_id,
        reposter_id=current_user.id,
        post_id=post_id,
        reposter_name=current_user.name
    )
    
    db.commit()
    db.refresh(repost)
    
    return {
        "reposted": True,
        "repost_id": repost.id,
        "message": "Post reposted successfully"
    }


@router.delete("/posts/{post_id}/repost")
async def delete_repost(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Удалить репост"""
    repost = db.query(Repost).filter(
        Repost.user_id == current_user.id,
        Repost.post_id == post_id
    ).first()
    
    if not repost:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Repost not found"
        )
    
    db.delete(repost)
    db.commit()
    
    return {"reposted": False, "message": "Repost deleted successfully"}


@router.get("/posts/{post_id}/reposts")
async def get_reposts(
    post_id: int,
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user)
):
    """Получить список пользователей, которые репостнули пост"""
    # Проверяем, существует ли пост
    post = db.query(Post).filter(
        Post.id == post_id,
        Post.deleted_at.is_(None)
    ).first()
    
    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found"
        )
    
    # Получаем репосты
    reposts = db.query(Repost).filter(
        Repost.post_id == post_id
    ).order_by(Repost.created_at.desc()).limit(limit).offset(offset).all()
    
    # Получаем информацию о пользователях
    user_ids = [r.user_id for r in reposts]
    users = db.query(User).filter(User.id.in_(user_ids)).all()
    users_dict = {u.id: u for u in users}
    
    reposts_data = []
    for repost in reposts:
        user = users_dict.get(repost.user_id)
        if user:
            reposts_data.append({
                "id": repost.id,
                "user": {
                    "id": user.id,
                    "name": user.name,
                    "username": user.username,
                    "avatar_url": user.avatar_url,
                },
                "comment": repost.comment,
                "created_at": repost.created_at.isoformat() if repost.created_at else None,
            })
    
    total = db.query(func.count(Repost.id)).filter(
        Repost.post_id == post_id
    ).scalar() or 0
    
    return {
        "reposts": reposts_data,
        "total": total,
    }


@router.get("/posts/{post_id}/is_reposted")
async def is_post_reposted(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Проверить, репостнул ли пользователь пост"""
    reposted = db.query(Repost).filter(
        Repost.user_id == current_user.id,
        Repost.post_id == post_id
    ).first() is not None
    
    return {"is_reposted": reposted}

