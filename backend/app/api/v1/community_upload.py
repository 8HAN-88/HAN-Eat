"""
Загрузка рилса (короткого видео) через POST /api/v1/community.
Принимает base64-видео, сохраняет файл и создаёт пост типа reel.
"""
import base64
import logging
import os
import uuid
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status, Request, Query
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy.orm import Session, joinedload

from app.api.dependencies import get_current_user_required
from app.core.database import get_db
from app.models.user import User
from app.models.post import Post
from app.models.like import Like
from app.models.comment import Comment
from app.services.feed_service import FeedService
from app.services.analytics_service import AnalyticsService

logger = logging.getLogger(__name__)

router = APIRouter()


def _reel_media_urls(body: object) -> tuple[str, Optional[str]]:
    """(video_url, thumbnail) из body.post."""
    if not isinstance(body, dict):
        return ("", None)
    video_url = (body.get("video_url") or "").strip() or ""
    thumb = body.get("video_thumbnail")
    thumb = thumb.strip() if isinstance(thumb, str) and thumb.strip() else None
    media = body.get("media")
    if isinstance(media, list):
        for item in media:
            if isinstance(item, dict) and item.get("type") == "video":
                u = item.get("url")
                if isinstance(u, str) and u.strip():
                    video_url = u.strip()
                t = item.get("thumbnail_url")
                if isinstance(t, str) and t.strip():
                    thumb = t.strip()
                break
    return (video_url, thumb)


def _post_ts_seconds(post: Post) -> int:
    dt = post.published_at or post.created_at
    if dt is None:
        return 0
    return int(dt.timestamp())


@router.get("/community")
async def list_community_videos(
    tag: Optional[str] = Query(None, description="Фильтр по тегу (подстрока, без #)"),
    limit: int = Query(50, ge=1, le=100),
    db: Session = Depends(get_db),
):
    """
    Публичная лента рилсов (посты type=reel) для экрана Community.
    Формат ответа совместим с клиентом: `{ "videos": [ ... ] }`.
    """
    q = (
        db.query(Post)
        .options(joinedload(Post.user))
        .filter(
            Post.type == "reel",
            Post.status == "published",
            Post.deleted_at.is_(None),
            *FeedService._recommendation_post_filters(),
        )
        .order_by(Post.published_at.desc().nullslast(), Post.id.desc())
    )
    fetch_limit = min(limit * 4, 200) if (tag and tag.strip()) else limit
    posts = q.limit(fetch_limit).all()

    tag_clean = (tag or "").strip().lower().lstrip("#")
    if tag_clean:
        filtered = []
        for p in posts:
            tags = [t.lower() for t in (p.tags or []) if isinstance(t, str)]
            if any(tag_clean == t or tag_clean in t for t in tags):
                filtered.append(p)
        posts = filtered[:limit]
    else:
        posts = posts[:limit]

    if not posts:
        return {"videos": []}

    ids = [p.id for p in posts]
    likes_rows = (
        db.query(Like.post_id, func.count(Like.id))
        .filter(Like.post_id.in_(ids))
        .group_by(Like.post_id)
        .all()
    )
    likes_map = {row[0]: int(row[1] or 0) for row in likes_rows}

    comments_rows = (
        db.query(Comment.post_id, func.count(Comment.id))
        .filter(Comment.post_id.in_(ids), Comment.deleted_at.is_(None))
        .group_by(Comment.post_id)
        .all()
    )
    comments_map = {row[0]: int(row[1] or 0) for row in comments_rows}

    videos = []
    for post in posts:
        video_url, thumbnail = _reel_media_urls(post.body)
        if not video_url:
            continue
        user = post.user
        author = (user.name or user.username or "").strip() if user else ""
        avatar = (user.avatar_url or "").strip() if user and user.avatar_url else None
        videos.append(
            {
                "id": post.id,
                "title": (post.title or "").strip(),
                "author": author,
                "avatar": avatar,
                "description": (post.description or "").strip(),
                "video_url": video_url,
                "thumbnail": thumbnail,
                "likes": likes_map.get(post.id, 0),
                "comments_count": comments_map.get(post.id, 0),
                "tags": list(post.tags or []),
                "created_at": _post_ts_seconds(post),
                "status": post.status or "published",
            }
        )

    return {"videos": videos}


@router.post("/community/{post_id}/like")
async def like_community_video(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Лайк рилса (alias для клиента Community)."""
    post = db.query(Post).filter(
        Post.id == post_id,
        Post.type == "reel",
        Post.deleted_at.is_(None),
    ).first()
    if not post:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Video not found")

    existing = (
        db.query(Like)
        .filter(Like.user_id == current_user.id, Like.post_id == post_id)
        .first()
    )
    if existing:
        likes_count = (
            db.query(func.count(Like.id)).filter(Like.post_id == post_id).scalar() or 0
        )
        return {"likes": int(likes_count), "likes_count": int(likes_count)}

    db.add(Like(user_id=current_user.id, post_id=post_id))
    db.commit()
    likes_count = (
        db.query(func.count(Like.id)).filter(Like.post_id == post_id).scalar() or 0
    )
    return {"likes": int(likes_count), "likes_count": int(likes_count)}


class CommunityUploadRequest(BaseModel):
    title: str
    author: str
    description: str = ""
    tags: list[str] = []
    video_base64: str
    thumbnail_base64: Optional[str] = None
    avatar: Optional[str] = None
    status: str = "pending"


@router.post("/community")
async def upload_community_video(
    request_body: CommunityUploadRequest,
    request: Request,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """
    Загрузить рилс: декодировать base64-видео, сохранить файл, создать пост типа reel.
    """
    try:
        video_bytes = base64.b64decode(request_body.video_base64)
    except Exception as e:
        logger.warning(f"Community upload: invalid base64 video: {e}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Некорректные данные видео (base64)",
        )

    if len(video_bytes) > 200 * 1024 * 1024:  # 200 MB
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Размер видео не более 200 МБ",
        )

    # Сохраняем видео в uploads (как mock)
    uploads_dir = os.path.join(os.getcwd(), "uploads")
    os.makedirs(uploads_dir, exist_ok=True)
    timestamp = datetime.utcnow().strftime("%Y/%m/%d")
    upload_id = str(uuid.uuid4())
    file_key = f"uploads/user_{current_user.id}/{timestamp}/{upload_id}.mp4"
    file_path = os.path.join(os.getcwd(), file_key)
    os.makedirs(os.path.dirname(file_path), exist_ok=True)
    with open(file_path, "wb") as f:
        f.write(video_bytes)

    base_url = str(request.base_url).rstrip("/")
    video_url = f"{base_url}/api/v1/uploads/file/{file_key}"

    body = {
        "media": [{"type": "video", "url": video_url}],
    }

    now = datetime.utcnow()
    post = Post(
        user_id=current_user.id,
        type="reel",
        title=request_body.title,
        description=request_body.description or "",
        body=body,
        publish_to=["feed", "reels"],
        visibility="public",
        tags=request_body.tags or [],
        status="published",
        published_at=now,
    )
    db.add(post)
    db.flush()

    from app.services.moderation_apply import raise_if_post_rejected, run_post_moderation

    scores = run_post_moderation(db, post, current_user)
    raise_if_post_rejected(db, post, scores)

    AnalyticsService(db).log_event(
        event_type="community_reel_upload",
        entity_type="post",
        entity_id=post.id,
        user_id=current_user.id,
        metadata={"tags": post.tags or []},
    )
    db.commit()
    db.refresh(post)

    try:
        from app.core.redis_client import get_redis
        from app.models.follower import Follower

        redis_client = get_redis()
        feed_service = FeedService(db, redis_client)
        followers = db.query(Follower.follower_id).filter(
            Follower.followee_id == current_user.id
        ).all()
        for row in followers:
            feed_service.invalidate_feed_cache(row[0])
        feed_service.invalidate_feed_cache(current_user.id)
    except Exception as e:
        logger.warning("Failed to invalidate feed cache after community reel upload: %s", e)

    created_at_ts = int(post.created_at.timestamp()) if post.created_at else 0

    return {
        "video": {
            "id": post.id,
            "title": post.title or "",
            "author": request_body.author,
            "description": post.description or "",
            "video_url": video_url,
            "thumbnail": None,
            "likes": 0,
            "tags": post.tags or [],
            "created_at": created_at_ts,
            "status": "published",
        }
    }
