"""
Creator tools: продвижение постов, отложенные публикации.
"""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user_required
from app.core.database import get_db
from app.models.post import Post
from app.models.user import User
from app.schemas.post import PostResponse
from app.services.analytics_service import AnalyticsService
from app.services.post_publish_service import (
    MAX_PROMOTED_POSTS,
    count_promoted_posts,
    parse_scheduled_at,
    pin_post,
    promote_post,
    unpin_post,
    unpromote_post,
)
from app.services.subscription_service import SubscriptionService

router = APIRouter()


@router.post("/recipes/analyze-nutrition")
async def analyze_recipe_nutrition_retired():
    """Kitchen nutrition AI removed — HanWe is a messenger."""
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail={
            "detail": "Kitchen features were removed. HanWe is a messenger.",
            "code": "kitchen_retired",
        },
    )


@router.post("/posts/{post_id}/promote", response_model=PostResponse)
async def promote_creator_post(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    post = promote_post(db, post_id, current_user.id)
    AnalyticsService(db).log_event(
        event_type="creator_post_promoted",
        entity_type="post",
        entity_id=post.id,
        user_id=current_user.id,
    )
    db.commit()
    db.refresh(post)
    return PostResponse.model_validate(post)


@router.get("/stats")
async def creator_stats(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = SubscriptionService(db)
    has_tools = svc.has_feature(current_user.id, "creator_tools")
    has_scheduled = svc.has_feature(current_user.id, "creator_scheduled_posts")
    has_analytics = svc.has_feature(current_user.id, "creator_analytics")
    promoted = count_promoted_posts(db, current_user.id) if has_tools else 0
    scheduled = (
        db.query(Post.id)
        .filter(
            Post.user_id == current_user.id,
            Post.status == "scheduled",
            Post.deleted_at.is_(None),
        )
        .count()
        if has_scheduled
        else 0
    )
    return {
        "has_creator": has_tools,
        "has_creator_tools": has_tools,
        "has_scheduled_posts": has_scheduled,
        "has_analytics": has_analytics,
        "promoted_count": promoted,
        "promoted_limit": MAX_PROMOTED_POSTS,
        "scheduled_count": scheduled,
    }


@router.post("/posts/{post_id}/pin", response_model=PostResponse)
async def pin_creator_post(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    post = pin_post(db, post_id, current_user.id)
    AnalyticsService(db).log_event(
        event_type="creator_post_pinned",
        entity_type="post",
        entity_id=post.id,
        user_id=current_user.id,
    )
    db.commit()
    db.refresh(post)
    return PostResponse.model_validate(post)


@router.delete("/posts/{post_id}/pin", response_model=PostResponse)
async def unpin_creator_post(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    post = unpin_post(db, post_id, current_user.id)
    AnalyticsService(db).log_event(
        event_type="creator_post_unpinned",
        entity_type="post",
        entity_id=post.id,
        user_id=current_user.id,
    )
    db.commit()
    db.refresh(post)
    return PostResponse.model_validate(post)


@router.delete("/posts/{post_id}/promote", response_model=PostResponse)
async def unpromote_creator_post(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    post = unpromote_post(db, post_id, current_user.id)
    db.commit()
    db.refresh(post)
    return PostResponse.model_validate(post)


@router.get("/posts/promoted")
async def list_promoted_posts(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Активные продвигаемые посты автора."""
    SubscriptionService(db).require_feature(
        current_user.id,
        "creator_tools",
        "Продвижение открывается функцией «Инструменты автора»",
    )
    posts = (
        db.query(Post)
        .filter(
            Post.user_id == current_user.id,
            Post.is_promoted.is_(True),
            Post.status == "published",
            Post.deleted_at.is_(None),
        )
        .order_by(Post.published_at.desc())
        .limit(MAX_PROMOTED_POSTS)
        .all()
    )
    return {
        "posts": [
            {
                "id": p.id,
                "title": p.title,
                "type": p.type,
                "channel_id": p.channel_id,
                "published_at": p.published_at.isoformat() if p.published_at else None,
            }
            for p in posts
        ],
        "limit": MAX_PROMOTED_POSTS,
    }


@router.get("/posts/scheduled")
async def list_scheduled_posts(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    SubscriptionService(db).require_feature(
        current_user.id,
        "creator_scheduled_posts",
        "Отложенные посты открываются одноимённой функцией подписки",
    )
    posts = (
        db.query(Post)
        .filter(
            Post.user_id == current_user.id,
            Post.status == "scheduled",
            Post.deleted_at.is_(None),
        )
        .order_by(Post.scheduled_publish_at.asc())
        .limit(50)
        .all()
    )
    return {
        "posts": [
            {
                "id": p.id,
                "title": p.title,
                "type": p.type,
                "channel_id": p.channel_id,
                "scheduled_publish_at": p.scheduled_publish_at.isoformat()
                if p.scheduled_publish_at
                else None,
            }
            for p in posts
        ]
    }


class ReschedulePostRequest(BaseModel):
    scheduled_publish_at: datetime = Field(..., description="Новое время публикации (UTC или с TZ)")


@router.patch("/posts/{post_id}/schedule")
async def reschedule_post(
    post_id: int,
    request: ReschedulePostRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    SubscriptionService(db).require_feature(
        current_user.id,
        "creator_scheduled_posts",
        "Отложенные посты открываются одноимённой функцией подписки",
    )

    post = (
        db.query(Post)
        .filter(
            Post.id == post_id,
            Post.user_id == current_user.id,
            Post.status == "scheduled",
            Post.deleted_at.is_(None),
        )
        .first()
    )
    if not post:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Scheduled post not found")

    scheduled_at = parse_scheduled_at(request.scheduled_publish_at)
    if scheduled_at is None or scheduled_at <= datetime.utcnow():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="scheduled_publish_at must be in the future",
        )

    post.scheduled_publish_at = scheduled_at
    db.commit()
    db.refresh(post)
    return {
        "id": post.id,
        "scheduled_publish_at": post.scheduled_publish_at.isoformat(),
    }


@router.delete("/posts/{post_id}/schedule", status_code=status.HTTP_204_NO_CONTENT)
async def cancel_scheduled_post(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    post = (
        db.query(Post)
        .filter(
            Post.id == post_id,
            Post.user_id == current_user.id,
            Post.status == "scheduled",
            Post.deleted_at.is_(None),
        )
        .first()
    )
    if not post:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Scheduled post not found")

    post.status = "deleted"
    post.deleted_at = datetime.utcnow()
    post.scheduled_publish_at = None
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
