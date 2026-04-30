"""
API endpoints для аналитики
"""
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from typing import Optional
from app.core.database import get_db
from app.api.dependencies import get_current_user_required
from app.models.user import User
from app.services.analytics_service import AnalyticsService

router = APIRouter()


@router.get("/posts/{post_id}")
async def get_post_analytics(
    post_id: int,
    days: int = Query(30, ge=1, le=365),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Получить аналитику поста (только для автора)"""
    from app.models.post import Post
    
    # Проверяем, что пост существует и пользователь является автором
    post = db.query(Post).filter(
        Post.id == post_id,
        Post.user_id == current_user.id
    ).first()
    
    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found or access denied"
        )
    
    analytics_service = AnalyticsService(db)
    analytics = analytics_service.get_post_analytics(
        post_id=post_id,
        author_id=current_user.id,
        days=days
    )
    
    return analytics


@router.get("/profile")
async def get_profile_analytics(
    days: int = Query(30, ge=1, le=365),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Получить аналитику профиля"""
    analytics_service = AnalyticsService(db)
    analytics = analytics_service.get_profile_analytics(
        user_id=current_user.id,
        days=days
    )
    
    return analytics

