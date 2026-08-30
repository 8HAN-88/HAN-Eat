"""
API endpoints для аналитики
"""
from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.dependencies import (
    get_current_user_required,
    require_entitlement_or_403,
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
    """Клиентские продуктовые события (paywall, открытие экранов и т.д.)."""
    allowed_prefixes = (
        "ai_scan_",
        "feed_",
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
    author_id = None
    if request.entity_type == "post" and request.entity_id > 0:
        from app.models.post import Post

        post = (
            db.query(Post)
            .filter(Post.id == request.entity_id, Post.deleted_at.is_(None))
            .first()
        )
        if post:
            author_id = post.user_id

    AnalyticsService(db).log_event(
        event_type=request.event_type,
        entity_type=request.entity_type,
        entity_id=request.entity_id,
        user_id=current_user.id,
        author_id=author_id,
        metadata=request.metadata,
    )
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/posts/{post_id}")
async def get_post_analytics(
    post_id: int,
    days: int = Query(30, ge=1, le=365),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Получить аналитику поста (автор + creator_analytics)."""
    from app.models.post import Post
    from app.services.subscription_service import SubscriptionService

    require_entitlement_or_403(
        db,
        current_user.id,
        "creator_analytics",
        "Аналитика доступна с тарифом Creator или Pro",
    )
    
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
    advanced = SubscriptionService(db).has_entitlement(
        current_user.id, "advanced_stats"
    )
    analytics["advanced_unlocked"] = advanced
    if advanced:
        analytics["advanced"] = analytics_service.get_post_advanced_stats(
            post_id=post_id, days=days
        )
    return analytics


@router.get("/profile")
async def get_profile_analytics(
    days: int = Query(30, ge=1, le=365),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Получить аналитику профиля (creator_analytics)."""
    from app.services.subscription_service import SubscriptionService

    require_entitlement_or_403(
        db,
        current_user.id,
        "creator_analytics",
        "Аналитика доступна с тарифом Creator или Pro",
    )
    analytics_service = AnalyticsService(db)
    analytics = analytics_service.get_profile_analytics(
        user_id=current_user.id,
        days=days
    )
    advanced = SubscriptionService(db).has_entitlement(
        current_user.id, "advanced_stats"
    )
    analytics["advanced_unlocked"] = advanced
    if advanced:
        analytics["advanced"] = analytics_service.get_profile_advanced_stats(
            user_id=current_user.id, days=days
        )
    return analytics


@router.get("/chat-channel")
async def get_chat_channel_analytics(
    days: int = Query(30, ge=1, le=365),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    require_entitlement_or_403(
        db,
        current_user.id,
        "creator_analytics",
        "Аналитика доступна с тарифом Creator или Pro",
    )
    analytics_service = AnalyticsService(db)
    return analytics_service.get_chat_channel_insights(
        user_id=current_user.id,
        days=days,
    )

