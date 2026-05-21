"""
API endpoints для аналитики
"""
from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.dependencies import (
    get_current_user_required,
    require_han_creator_subscriber,
)
from app.core.database import get_db
from app.models.user import User
from app.services.analytics_service import AnalyticsService

router = APIRouter()


class ClientEventRequest(BaseModel):
    event_type: str = Field(..., max_length=64)
    entity_type: str = Field(default="app", max_length=32)
    entity_id: int = Field(default=0, ge=0)
    metadata: Optional[Dict[str, Any]] = None


@router.post("/events", status_code=status.HTTP_204_NO_CONTENT, response_class=Response)
async def log_client_event(
    request: ClientEventRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Клиентские продуктовые события (ai_scan_paywall, и т.д.)."""
    allowed_prefixes = (
        "ai_scan_",
        "meal_plan_",
        "moderation_",
        "subscription_",
        "report_",
        "community_",
    )
    if not any(request.event_type.startswith(p) for p in allowed_prefixes):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Event type not allowed",
        )
    AnalyticsService(db).log_event(
        event_type=request.event_type,
        entity_type=request.entity_type,
        entity_id=request.entity_id,
        user_id=current_user.id,
        metadata=request.metadata,
    )
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/posts/{post_id}")
async def get_post_analytics(
    post_id: int,
    days: int = Query(30, ge=1, le=365),
    current_user: User = Depends(require_han_creator_subscriber),
    db: Session = Depends(get_db),
):
    """Получить аналитику поста (автор + тариф Creator/Pro)."""
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
    current_user: User = Depends(require_han_creator_subscriber),
    db: Session = Depends(get_db),
):
    """Получить аналитику профиля (тариф Creator/Pro)."""
    analytics_service = AnalyticsService(db)
    analytics = analytics_service.get_profile_analytics(
        user_id=current_user.id,
        days=days
    )
    
    return analytics

