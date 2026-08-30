"""
Отложенная публикация и продвижение постов (Creator).
"""
from __future__ import annotations

from datetime import datetime
from typing import Optional

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.core.entitlements import HAN_CREATOR_REQUIRED_CODE
from app.api.dependencies import require_entitlement_or_403
from app.models.post import Post
from app.models.user import User

MAX_PROMOTED_POSTS = 5


def count_promoted_posts(db: Session, user_id: int) -> int:
    return (
        db.query(Post.id)
        .filter(
            Post.user_id == user_id,
            Post.is_promoted.is_(True),
            Post.status == "published",
            Post.deleted_at.is_(None),
        )
        .count()
    )


def parse_scheduled_at(value: Optional[datetime]) -> Optional[datetime]:
    if value is None:
        return None
    if value.tzinfo is not None:
        return value.replace(tzinfo=None)
    return value


def require_creator_for_schedule(db: Session, user: User, scheduled_at: Optional[datetime]) -> None:
    scheduled_at = parse_scheduled_at(scheduled_at)
    if scheduled_at is None:
        return
    if scheduled_at <= datetime.utcnow():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="scheduled_publish_at must be in the future",
        )
    require_entitlement_or_403(
        db,
        user.id,
        "creator_scheduled_posts",
        "Отложенная публикация доступна с тарифом HanWe Creator или Pro",
        code=HAN_CREATOR_REQUIRED_CODE,
    )


def defer_post_if_scheduled(
    post: Post,
    scheduled_at: Optional[datetime],
) -> None:
    """После модерации: отложить публикацию вместо немедленного выхода в ленту."""
    scheduled_at = parse_scheduled_at(scheduled_at)
    if scheduled_at is None or scheduled_at <= datetime.utcnow():
        return
    if post.status != "published":
        return
    post.status = "scheduled"
    post.published_at = None
    post.scheduled_publish_at = scheduled_at


def publish_due_scheduled_posts(db: Session) -> int:
    """Публикует посты со статусом scheduled, у которых наступило время."""
    now = datetime.utcnow()
    due = (
        db.query(Post)
        .filter(
            Post.status == "scheduled",
            Post.scheduled_publish_at.isnot(None),
            Post.scheduled_publish_at <= now,
            Post.deleted_at.is_(None),
        )
        .limit(50)
        .all()
    )
    if not due:
        return 0

    from app.services.notification_service import NotificationService

    published = 0
    for post in due:
        post.status = "published"
        post.published_at = now
        post.scheduled_publish_at = None
        published += 1
        try:
            NotificationService(db).create_notification(
                user_id=post.user_id,
                type="post_scheduled_published",
                title="Запланированный пост опубликован",
                body=post.title or "Ваш пост вышел в ленте",
                entity_type="post",
                entity_id=post.id,
                data={
                    "post_id": post.id,
                    "channel_id": post.channel_id,
                    "action": "open_post",
                },
            )
        except Exception:
            pass
        try:
            if post.channel_id:
                from app.services.channel_notification_service import (
                    send_channel_post_notification,
                )

                send_channel_post_notification(
                    db=db,
                    channel_id=post.channel_id,
                    post_id=post.id,
                    post_type=post.type,
                    post_title=post.title,
                    author_id=post.user_id,
                )
        except Exception:
            pass

    return published


def promote_post(db: Session, post_id: int, user_id: int) -> Post:
    post = (
        db.query(Post)
        .filter(Post.id == post_id, Post.deleted_at.is_(None))
        .first()
    )
    if not post:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Post not found")
    if post.user_id != user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not your post")
    if post.status != "published":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only published posts can be promoted",
        )
    require_entitlement_or_403(
        db,
        user_id,
        "creator_promotion",
        "Продвижение доступно с тарифом HanWe Creator или Pro",
        code=HAN_CREATOR_REQUIRED_CODE,
    )

    active_promoted = (
        db.query(Post.id)
        .filter(
            Post.user_id == user_id,
            Post.is_promoted.is_(True),
            Post.status == "published",
            Post.deleted_at.is_(None),
        )
        .count()
    )
    if active_promoted >= MAX_PROMOTED_POSTS and not post.is_promoted:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Лимит продвигаемых постов: {MAX_PROMOTED_POSTS}",
        )

    post.is_promoted = True
    return post


def unpromote_post(db: Session, post_id: int, user_id: int) -> Post:
    post = (
        db.query(Post)
        .filter(Post.id == post_id, Post.deleted_at.is_(None))
        .first()
    )
    if not post:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Post not found")
    if post.user_id != user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not your post")
    require_entitlement_or_403(
        db,
        user_id,
        "creator_promotion",
        "Продвижение доступно с тарифом HanWe Creator или Pro",
        code=HAN_CREATOR_REQUIRED_CODE,
    )
    post.is_promoted = False
    return post


def pin_post(db: Session, post_id: int, user_id: int) -> Post:
    post = (
        db.query(Post)
        .filter(Post.id == post_id, Post.deleted_at.is_(None))
        .first()
    )
    if not post:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Post not found")
    if post.user_id != user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not your post")
    if post.status != "published":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only published posts can be pinned",
        )
    if not post.channel_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only channel posts can be pinned",
        )
    require_entitlement_or_403(
        db,
        user_id,
        "creator_pinned",
        "Закрепление доступно с тарифом HanWe Creator или Pro",
        code=HAN_CREATOR_REQUIRED_CODE,
    )

    others = (
        db.query(Post)
        .filter(
            Post.channel_id == post.channel_id,
            Post.is_pinned.is_(True),
            Post.id != post.id,
            Post.deleted_at.is_(None),
        )
        .all()
    )
    for other in others:
        other.is_pinned = False

    post.is_pinned = True
    return post


def unpin_post(db: Session, post_id: int, user_id: int) -> Post:
    post = (
        db.query(Post)
        .filter(Post.id == post_id, Post.deleted_at.is_(None))
        .first()
    )
    if not post:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Post not found")
    if post.user_id != user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not your post")
    require_entitlement_or_403(
        db,
        user_id,
        "creator_pinned",
        "Закрепление доступно с тарифом HanWe Creator или Pro",
        code=HAN_CREATOR_REQUIRED_CODE,
    )
    post.is_pinned = False
    return post
