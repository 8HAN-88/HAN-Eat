"""
API endpoints для модерации
"""
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import Optional, List
from pydantic import BaseModel
from app.core.database import get_db
from app.api.dependencies import get_current_user_required, get_current_moderator_required
from app.models.user import User
from app.models.post import Post
from app.models.comment import Comment
from app.models.moderation_queue import ModerationQueue, ModerationStatus, ModerationReason
from app.services.moderation_service import ModerationService
from app.services.notification_service import NotificationService

router = APIRouter()


class ApproveRequest(BaseModel):
    comment: Optional[str] = None


class RejectRequest(BaseModel):
    reason: str  # spam | inappropriate | copyright | other
    comment: str


@router.get("/pending")
async def get_pending_moderation(
    content_type: Optional[str] = Query(None),  # post | comment | user | all
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_moderator_required)
):
    """Получить очередь модерации (только для модераторов и админов)"""
    
    query = db.query(ModerationQueue).filter(
        ModerationQueue.status == "pending"
    )
    
    if content_type and content_type != "all":
        query = query.filter(ModerationQueue.content_type == content_type)
    
    items = query.order_by(ModerationQueue.created_at.desc()).limit(limit).offset(offset).all()
    
    # Обогащаем данными о контенте
    enriched_items = []
    for item in items:
        content_data = None
        user_data = None
        
        if item.content_type == "post":
            post = db.query(Post).filter(Post.id == item.content_id).first()
            if post:
                author = db.query(User).filter(User.id == post.user_id).first()
                content_data = {
                    "id": post.id,
                    "type": post.type,
                    "title": post.title,
                    "description": post.description,
                    "author": {
                        "id": author.id if author else None,
                        "name": author.name if author else None,
                        "username": author.username if author else None,
                    } if author else None,
                }
        elif item.content_type == "comment":
            comment = db.query(Comment).filter(Comment.id == item.content_id).first()
            if comment:
                author = db.query(User).filter(User.id == comment.user_id).first()
                content_data = {
                    "id": comment.id,
                    "text": comment.text,
                    "post_id": comment.post_id,
                    "author": {
                        "id": author.id if author else None,
                        "name": author.name if author else None,
                        "username": author.username if author else None,
                    } if author else None,
                }
        
        if item.user_id:
            user = db.query(User).filter(User.id == item.user_id).first()
            if user:
                user_data = {
                    "id": user.id,
                    "name": user.name,
                    "username": user.username,
                    "avatar_url": user.avatar_url,
                }
        
        enriched_items.append({
            "id": item.id,
            "content_type": item.content_type,
            "content_id": item.content_id,
            "content": content_data,
            "user": user_data,
            "reason": item.reason,
            "flagged_by_user_id": item.flagged_by_user_id,
            "created_at": item.created_at.isoformat() if item.created_at else None,
        })
    
    total = db.query(func.count(ModerationQueue.id)).filter(
        ModerationQueue.status == "pending"
    ).scalar() or 0
    
    return {
        "items": enriched_items,
        "total": total,
    }


@router.post("/{item_id}/approve")
async def approve_content(
    item_id: int,
    request: ApproveRequest,
    current_user: User = Depends(get_current_moderator_required),
    db: Session = Depends(get_db)
):
    """Одобрить контент"""
    from datetime import datetime
    
    item = db.query(ModerationQueue).filter(ModerationQueue.id == item_id).first()
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Moderation item not found"
        )
    
    if item.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Item already moderated"
        )
    
    # Обновляем статус контента и получаем автора для уведомления
    author_id = None
    content_label = "Контент"
    if item.content_type == "post":
        post = db.query(Post).filter(Post.id == item.content_id).first()
        if post:
            author_id = post.user_id
            content_label = "Рилс" if post.type == "reel" else "Пост"
            post.status = "published"
            if not post.published_at:
                post.published_at = datetime.utcnow()
    elif item.content_type == "comment":
        comment = db.query(Comment).filter(Comment.id == item.content_id).first()
        if comment:
            author_id = comment.user_id
            content_label = "Комментарий"
            comment.deleted_at = None  # Убираем пометку об удалении, если была
    
    # Обновляем запись модерации
    item.status = "approved"
    item.moderated_by_user_id = current_user.id
    item.moderation_comment = request.comment
    item.moderated_at = datetime.utcnow()
    
    # Уведомляем автора об одобрении
    if author_id:
        notif_service = NotificationService(db)
        notif_service.create_notification(
            user_id=author_id,
            type="moderation_approved",
            title="Модерация пройдена",
            body=f"Ваш {content_label} одобрен и опубликован.",
            entity_type=item.content_type,
            entity_id=item.content_id,
            actor_id=current_user.id,
            data={
                "content_type": item.content_type,
                "content_id": item.content_id,
                "action": "approved",
            },
        )
    
    db.commit()
    
    return {
        "approved": True,
        "content_type": item.content_type,
        "content_id": item.content_id,
        "status": "published" if item.content_type == "post" else "approved"
    }


@router.post("/{item_id}/reject")
async def reject_content(
    item_id: int,
    request: RejectRequest,
    current_user: User = Depends(get_current_moderator_required),
    db: Session = Depends(get_db)
):
    """Отклонить контент"""
    from datetime import datetime
    
    item = db.query(ModerationQueue).filter(ModerationQueue.id == item_id).first()
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Moderation item not found"
        )
    
    if item.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Item already moderated"
        )
    
    # Обновляем статус контента и получаем автора для уведомления
    author_id = None
    content_label = "Контент"
    if item.content_type == "post":
        post = db.query(Post).filter(Post.id == item.content_id).first()
        if post:
            author_id = post.user_id
            content_label = "Рилс" if post.type == "reel" else "Пост"
            post.status = "rejected"
    elif item.content_type == "comment":
        comment = db.query(Comment).filter(Comment.id == item.content_id).first()
        if comment:
            author_id = comment.user_id
            content_label = "Комментарий"
            comment.deleted_at = datetime.utcnow()
    
    # Обновляем запись модерации
    item.status = "rejected"
    item.moderated_by_user_id = current_user.id
    item.rejection_reason = request.reason
    item.moderation_comment = request.comment
    item.moderated_at = datetime.utcnow()
    
    # Уведомляем автора об отклонении
    if author_id:
        reason_text = {"spam": "спам", "inappropriate": "неподходящий контент", "copyright": "нарушение авторских прав", "other": "другое"}.get(request.reason, request.reason)
        notif_service = NotificationService(db)
        notif_service.create_notification(
            user_id=author_id,
            type="moderation_rejected",
            title="Модерация не пройдена",
            body=f"Ваш {content_label} отклонён. Причина: {reason_text}. {request.comment or ''}".strip(),
            entity_type=item.content_type,
            entity_id=item.content_id,
            actor_id=current_user.id,
            data={
                "content_type": item.content_type,
                "content_id": item.content_id,
                "action": "rejected",
                "reason": request.reason,
            },
        )
    
    db.commit()
    
    return {
        "rejected": True,
        "content_type": item.content_type,
        "content_id": item.content_id,
        "status": "rejected"
    }
