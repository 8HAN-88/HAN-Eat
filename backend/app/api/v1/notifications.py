"""
API endpoints для уведомлений
"""
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import Optional, List
from pydantic import BaseModel
from datetime import datetime
from app.core.database import get_db
from app.api.dependencies import get_current_user_required
from app.models.user import User
from app.models.notification import Notification
from app.services.push_service import get_push_service

router = APIRouter()


class MarkReadRequest(BaseModel):
    read: bool = True


@router.get("")
async def get_notifications(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    unread_only: bool = Query(False),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Получить список уведомлений пользователя"""
    query = db.query(Notification).filter(
        Notification.user_id == current_user.id
    )
    
    if unread_only:
        query = query.filter(Notification.is_read == False)
    
    notifications = query.order_by(
        Notification.created_at.desc()
    ).limit(limit).offset(offset).all()
    
    # Обогащаем данными об акторе
    enriched_notifications = []
    for notif in notifications:
        actor = None
        if notif.actor_id:
            actor = db.query(User).filter(User.id == notif.actor_id).first()
        
        enriched_notifications.append({
            "id": notif.id,
            "type": notif.type,
            "title": notif.title,
            "body": notif.body,
            "entity_type": notif.entity_type,
            "entity_id": notif.entity_id,
            "actor": {
                "id": actor.id if actor else None,
                "name": actor.name if actor else None,
                "username": actor.username if actor else None,
                "avatar_url": actor.avatar_url if actor else None,
            } if actor else None,
            "is_read": notif.is_read,
            "read_at": notif.read_at.isoformat() if notif.read_at else None,
            "created_at": notif.created_at.isoformat() if notif.created_at else None,
            "data": notif.data,
        })
    
    # Получаем общее количество непрочитанных
    unread_count = db.query(func.count(Notification.id)).filter(
        Notification.user_id == current_user.id,
        Notification.is_read == False
    ).scalar() or 0
    
    return {
        "notifications": enriched_notifications,
        "unread_count": unread_count,
        "has_more": len(notifications) == limit,
    }


@router.put("/{notification_id}/read")
async def mark_notification_read(
    notification_id: int,
    request: MarkReadRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Пометить уведомление как прочитанное/непрочитанное"""
    notification = db.query(Notification).filter(
        Notification.id == notification_id,
        Notification.user_id == current_user.id
    ).first()
    
    if not notification:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Notification not found"
        )
    
    notification.is_read = request.read
    if request.read:
        notification.read_at = datetime.utcnow()
    else:
        notification.read_at = None
    
    db.commit()
    
    return {
        "id": notification.id,
        "is_read": notification.is_read,
    }


@router.put("/read-all")
async def mark_all_read(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Пометить все уведомления как прочитанные"""
    updated = db.query(Notification).filter(
        Notification.user_id == current_user.id,
        Notification.is_read == False
    ).update({
        "is_read": True,
        "read_at": datetime.utcnow()
    })
    
    db.commit()
    
    return {
        "marked_read": updated,
        "message": f"Marked {updated} notifications as read"
    }


@router.get("/unread-count")
async def get_unread_count(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Получить количество непрочитанных уведомлений"""
    count = db.query(func.count(Notification.id)).filter(
        Notification.user_id == current_user.id,
        Notification.is_read == False
    ).scalar() or 0
    
    return {
        "unread_count": count
    }


@router.post("/cleanup-tokens")
async def cleanup_invalid_tokens(
    batch_size: int = Query(100, ge=1, le=1000),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """
    Очистить недействительные FCM токены
    
    Проверяет токены пользователей и удаляет недействительные.
    Доступно только для администраторов.
    """
    # Проверка прав администратора
    if not current_user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only administrators can cleanup tokens"
        )
    
    push_service = get_push_service()
    
    if not push_service.enabled:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Push service is not available"
        )
    
    try:
        removed_count = push_service.cleanup_invalid_tokens(db, batch_size=batch_size)
        
        return {
            "success": True,
            "removed_count": removed_count,
            "message": f"Cleaned up {removed_count} invalid FCM tokens"
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to cleanup tokens: {str(e)}"
        )

