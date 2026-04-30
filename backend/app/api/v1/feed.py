"""
API endpoints для ленты
"""
from fastapi import APIRouter, Depends, Query
from typing import Optional
from app.core.database import get_db
from app.api.dependencies import get_current_user_required
from app.models.user import User
from app.services.feed_service import FeedService
from app.core.redis_client import get_redis

router = APIRouter()


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

