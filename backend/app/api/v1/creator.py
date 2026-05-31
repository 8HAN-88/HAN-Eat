"""
Creator tools: продвижение постов, отложенные публикации.
"""
from datetime import datetime
from typing import List, Optional

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
    promote_post,
    unpromote_post,
)
from app.services.subscription_service import SubscriptionService
from app.services.recipe_nutrition_gpt_service import analyze_recipe_nutrition_gpt

router = APIRouter()


class AnalyzeRecipeNutritionRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=500)
    description: Optional[str] = None
    ingredients: List[str] = Field(default_factory=list)
    steps: List[str] = Field(default_factory=list)
    servings: Optional[int] = Field(default=1, ge=1, le=50)
    language: str = Field(default="ru", max_length=8)


@router.post("/recipes/analyze-nutrition")
async def analyze_recipe_nutrition(
    request: AnalyzeRecipeNutritionRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """AI-оценка КБЖУ рецепта (тариф Creator или Pro)."""
    if not SubscriptionService(db).has_creator_access(current_user.id):
        from app.core.entitlements import HAN_CREATOR_REQUIRED_CODE

        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": HAN_CREATOR_REQUIRED_CODE,
                "message": "AI-расчёт питания доступен с тарифом Creator или Pro",
            },
        )

    result = analyze_recipe_nutrition_gpt(
        title=request.title,
        description=request.description,
        ingredients=request.ingredients,
        steps=request.steps,
        servings=request.servings,
        language=request.language,
    )
    if not result:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Не удалось рассчитать питание. Попробуйте позже.",
        )

    AnalyticsService(db).log_event(
        event_type="creator_recipe_nutrition_ai",
        entity_type="user",
        entity_id=current_user.id,
        user_id=current_user.id,
        metadata={
            "title_len": len(request.title),
            "ingredients_count": len(request.ingredients),
            "confidence": result.get("confidence"),
        },
    )
    db.commit()
    return result


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
    has_creator = svc.has_creator_access(current_user.id)
    promoted = count_promoted_posts(db, current_user.id) if has_creator else 0
    scheduled = (
        db.query(Post.id)
        .filter(
            Post.user_id == current_user.id,
            Post.status == "scheduled",
            Post.deleted_at.is_(None),
        )
        .count()
        if has_creator
        else 0
    )
    return {
        "has_creator": has_creator,
        "promoted_count": promoted,
        "promoted_limit": MAX_PROMOTED_POSTS,
        "scheduled_count": scheduled,
    }


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
    if not SubscriptionService(db).has_creator_access(current_user.id):
        from app.core.entitlements import HAN_CREATOR_REQUIRED_CODE

        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": HAN_CREATOR_REQUIRED_CODE,
                "message": "Требуется тариф Creator или Pro",
            },
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
    if not SubscriptionService(db).has_creator_access(current_user.id):
        from app.core.entitlements import HAN_CREATOR_REQUIRED_CODE

        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": HAN_CREATOR_REQUIRED_CODE,
                "message": "Требуется тариф Creator или Pro",
            },
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
    if not SubscriptionService(db).has_creator_access(current_user.id):
        from app.core.entitlements import HAN_CREATOR_REQUIRED_CODE

        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": HAN_CREATOR_REQUIRED_CODE,
                "message": "Требуется тариф Creator или Pro",
            },
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
