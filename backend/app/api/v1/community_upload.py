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
from app.core.config import settings
from app.core.database import get_db
from app.models.user import User
from app.models.post import Post
from app.models.like import Like
from app.models.comment import Comment
from app.core.media_urls import normalize_media_url, public_base_url
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

    from app.models.community import Channel

    channel_ids = {p.channel_id for p in posts if p.channel_id}
    channels_by_id = {}
    if channel_ids:
        for ch in db.query(Channel).filter(Channel.id.in_(channel_ids)).all():
            channels_by_id[ch.id] = ch

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
        channel = channels_by_id.get(post.channel_id) if post.channel_id else None
        if channel is not None:
            author = (channel.name or "").strip()
            avatar = (channel.avatar_url or "").strip() if channel.avatar_url else None
        else:
            user = post.user
            author = (user.name or user.username or "").strip() if user else ""
            avatar = (user.avatar_url or "").strip() if user and user.avatar_url else None
        item = {
            "id": post.id,
            "title": (post.title or "").strip(),
            "author": author,
            "avatar": avatar,
            "description": (post.description or "").strip(),
            "video_url": normalize_media_url(video_url),
            "thumbnail": normalize_media_url(thumbnail) if thumbnail else None,
            "likes": likes_map.get(post.id, 0),
            "comments_count": comments_map.get(post.id, 0),
            "tags": list(post.tags or []),
            "created_at": _post_ts_seconds(post),
            "status": post.status or "published",
        }
        if post.channel_id:
            item["channel_id"] = post.channel_id
            if channel is not None:
                item["channel"] = {
                    "id": channel.id,
                    "name": channel.name,
                    "slug": channel.slug,
                    "avatar_url": normalize_media_url(channel.avatar_url)
                    if channel.avatar_url
                    else None,
                }
        videos.append(item)

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
    video_base64: Optional[str] = None
    video_url: Optional[str] = None
    thumbnail_base64: Optional[str] = None
    thumbnail_url: Optional[str] = None
    avatar: Optional[str] = None
    status: str = "pending"
    channel_id: Optional[int] = None


@router.post("/community")
async def upload_community_video(
    request_body: CommunityUploadRequest,
    request: Request,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """
    Загрузить рилс: принять video_url (предпочтительно) или base64-видео, создать пост type=reel.
    """
    from app.services.emoji_pack_service import EmojiPackService

    EmojiPackService(db).require_send_tokens_http(
        current_user.id,
        request_body.title,
        request_body.description,
        request_body.author,
        *(request_body.tags or []),
    )
    video_url: Optional[str] = None
    thumbnail_url: Optional[str] = None

    if request_body.video_url and request_body.video_url.strip():
        video_url = normalize_media_url(request_body.video_url.strip())
    elif request_body.video_base64:
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

        uploads_dir = os.path.join(os.getcwd(), "uploads")
        os.makedirs(uploads_dir, exist_ok=True)
        timestamp = datetime.utcnow().strftime("%Y/%m/%d")
        upload_id = str(uuid.uuid4())
        file_key = f"uploads/user_{current_user.id}/{timestamp}/{upload_id}.mp4"
        file_path = os.path.join(os.getcwd(), file_key)
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        with open(file_path, "wb") as f:
            f.write(video_bytes)

        base_url = public_base_url()
        video_url = normalize_media_url(f"{base_url}/api/v1/uploads/file/{file_key}")
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Укажите video_url или video_base64",
        )

    if request_body.thumbnail_url and request_body.thumbnail_url.strip():
        thumbnail_url = normalize_media_url(request_body.thumbnail_url.strip())
    elif request_body.thumbnail_base64:
        try:
            thumb_bytes = base64.b64decode(request_body.thumbnail_base64)
            uploads_dir = os.path.join(os.getcwd(), "uploads")
            os.makedirs(uploads_dir, exist_ok=True)
            timestamp = datetime.utcnow().strftime("%Y/%m/%d")
            thumb_id = str(uuid.uuid4())
            thumb_key = f"uploads/user_{current_user.id}/{timestamp}/{thumb_id}.jpg"
            thumb_path = os.path.join(os.getcwd(), thumb_key)
            os.makedirs(os.path.dirname(thumb_path), exist_ok=True)
            with open(thumb_path, "wb") as f:
                f.write(thumb_bytes)
            base_url = public_base_url()
            thumbnail_url = normalize_media_url(
                f"{base_url}/api/v1/uploads/file/{thumb_key}"
            )
        except Exception as e:
            logger.warning(f"Community upload: invalid base64 thumbnail: {e}")

    media_item: dict = {"type": "video", "url": video_url}
    if thumbnail_url:
        media_item["thumbnail_url"] = thumbnail_url
    body = {
        "media": [media_item],
    }

    channel = None
    publish_to = ["feed", "reels"]
    channel_id = request_body.channel_id
    if channel_id is not None:
        from app.models.community import Channel
        from app.services.channel_membership_service import (
            get_membership,
            has_channel_permission,
        )

        channel = db.query(Channel).filter(Channel.id == channel_id).first()
        if not channel:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Channel not found",
            )
        member = get_membership(db, channel_id, current_user.id)
        if not has_channel_permission(
            channel,
            member,
            current_user,
            "create_posts",
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Недостаточно прав для публикации постов в канале",
            )
        publish_to = [f"channel:{channel_id}"]
        if channel.auto_publish_to_feed:
            publish_to.insert(0, "feed")
        if channel.auto_publish_reels:
            publish_to.append("reels")

    now = datetime.utcnow()
    post = Post(
        user_id=current_user.id,
        channel_id=channel_id if channel else None,
        type="reel",
        title=request_body.title,
        description=request_body.description or "",
        body=body,
        publish_to=publish_to,
        visibility="public",
        tags=request_body.tags or [],
        status="published",
        published_at=now,
    )
    db.add(post)
    if channel is not None:
        channel.posts_count = (channel.posts_count or 0) + 1
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
        from app.services.user_stats_cache import invalidate_user_stats_cache

        invalidate_user_stats_cache([current_user.id])
    except Exception as e:
        logger.warning("Failed to invalidate user stats after reel upload: %s", e)

    try:
        from app.core.redis_client import get_redis
        from app.models.follower import Follower
        from app.models.community_member import ChannelMember
        from app.services.channel_membership_service import MEMBER_STATUS_ACTIVE

        redis_client = get_redis()
        feed_service = FeedService(db, redis_client)
        if channel_id is not None:
            channel_members = db.query(ChannelMember.user_id).filter(
                ChannelMember.channel_id == channel_id,
                ChannelMember.status == MEMBER_STATUS_ACTIVE,
            ).all()
            for member_user_id, in channel_members:
                feed_service.invalidate_feed_cache(member_user_id)
        followers = db.query(Follower.follower_id).filter(
            Follower.followee_id == current_user.id
        ).all()
        for row in followers:
            feed_service.invalidate_feed_cache(row[0])
        feed_service.invalidate_feed_cache(current_user.id)
    except Exception as e:
        logger.warning("Failed to invalidate feed cache after community reel upload: %s", e)

    if channel_id is not None:
        try:
            from app.services.channel_notification_service import (
                send_channel_post_notification,
            )

            send_channel_post_notification(
                db=db,
                channel_id=channel_id,
                post_id=post.id,
                post_type="reel",
                post_title=request_body.title,
                author_id=current_user.id,
            )
        except Exception as e:
            logger.warning("Failed to send channel reel notification: %s", e)

    created_at_ts = int(post.created_at.timestamp()) if post.created_at else 0

    display_author = request_body.author
    display_avatar = None
    if channel is not None:
        display_author = (channel.name or "").strip() or display_author
        display_avatar = (
            normalize_media_url(channel.avatar_url) if channel.avatar_url else None
        )

    video_payload = {
        "id": post.id,
        "title": post.title or "",
        "author": display_author,
        "description": post.description or "",
        "video_url": normalize_media_url(video_url),
        "thumbnail": normalize_media_url(thumbnail_url) if thumbnail_url else None,
        "likes": 0,
        "tags": post.tags or [],
        "created_at": created_at_ts,
        "status": "published",
    }
    if display_avatar:
        video_payload["avatar"] = display_avatar
    if channel_id is not None:
        video_payload["channel_id"] = channel_id
        if channel is not None:
            video_payload["channel"] = {
                "id": channel.id,
                "name": channel.name,
                "slug": channel.slug,
                "avatar_url": display_avatar,
            }

    return {"video": video_payload}
