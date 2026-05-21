"""
API endpoints для ленты
"""
from fastapi import APIRouter, Depends, Query, HTTPException, status
from fastapi.responses import Response
from pydantic import BaseModel
from typing import Optional
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.api.dependencies import get_current_user_required
from app.models.user import User
from app.models.post import Post
from app.services.feed_service import FeedService
from app.services.analytics_service import AnalyticsService
from app.core.redis_client import get_redis

router = APIRouter()


class DismissPostRequest(BaseModel):
    post_id: int


@router.get("")
async def get_feed(
    cursor: Optional[str] = Query(None),
    limit: int = Query(20, ge=1, le=50),
    feed_type: str = Query("all", regex="^(all|reels|recipes|photos)$"),
    following_only: bool = Query(False, description="Показывать только посты от подписок"),
    current_user: User = Depends(get_current_user_required),
    db = Depends(get_db),
    redis = Depends(get_redis)
):
    """Получить персональную ленту"""
    feed_service = FeedService(db, redis)
    result = feed_service.get_feed(
        user_id=current_user.id,
        cursor=cursor,
        limit=limit,
        feed_type=feed_type,
        following_only=following_only
    )
    return {
        "items": result["items"],
        "next_cursor": result["next_cursor"],
        "has_more": result["has_more"]
    }


@router.post("/dismiss", status_code=status.HTTP_204_NO_CONTENT)
async def dismiss_post_from_feed(
    body: DismissPostRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
    redis=Depends(get_redis),
):
    """
    Явно скрыть пост из персональной ленты (сигнал для ранжирования).
    Идемпотентно: повторные вызовы только добавляют события аналитики.
    """
    post = (
        db.query(Post)
        .filter(Post.id == body.post_id, Post.deleted_at.is_(None))
        .first()
    )
    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found",
        )

    analytics = AnalyticsService(db)
    analytics.log_event(
        event_type="dismiss",
        entity_type="post",
        entity_id=body.post_id,
        user_id=current_user.id,
        author_id=post.user_id,
        metadata={"source": "feed_dismiss"},
    )
    db.commit()
    FeedService(db, redis).invalidate_feed_cache(current_user.id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)

