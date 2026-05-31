"""
Сервис для отправки уведомлений о событиях в каналах
"""
import logging
from datetime import datetime
from typing import Optional

from sqlalchemy.orm import Session

from app.models.community import Channel
from app.models.community_member import ChannelMember
from app.services.channel_membership_service import MEMBER_STATUS_ACTIVE
from app.models.notification import Notification
from app.models.user import User
from app.services.push_service import get_push_service

logger = logging.getLogger(__name__)


def _send_channel_push_batch(db: Session, notifications: list[Notification]) -> None:
    """Отправить push подписчикам канала через FCM."""
    if not notifications:
        return

    push_service = get_push_service()
    if not push_service.enabled:
        return

    user_ids = [n.user_id for n in notifications]
    users = {
        u.id: u
        for u in db.query(User).filter(User.id.in_(user_ids)).all()
    }

    batch: list[tuple[User, Notification]] = []
    for notification in notifications:
        user = users.get(notification.user_id)
        if user and user.fcm_token:
            batch.append((user, notification))

    if not batch:
        return

    try:
        push_service.send_batch_push_notifications(batch)
    except Exception as e:
        logger.warning("Error sending channel push notifications: %s", e, exc_info=True)


def send_channel_post_notification(
    db: Session,
    channel_id: int,
    post_id: int,
    post_type: str,
    post_title: Optional[str] = None,
    author_id: int = None
):
    """
    Отправить уведомления подписчикам канала о новом посте

    Типы уведомлений:
    - channel_post: новый пост в канале
    - channel_recipe: новый рецепт в канале
    - channel_video: новое видео в канале
    - channel_announcement: объявление от автора
    """
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        return

    subscribers = db.query(ChannelMember).filter(
        ChannelMember.channel_id == channel_id,
        ChannelMember.status == MEMBER_STATUS_ACTIVE,
        ChannelMember.user_id != author_id,
    ).all()

    if not subscribers:
        return

    notification_type = "channel_post"
    title = f"Новый пост в канале {channel.name}"
    body = post_title or "Новый пост"

    if post_type == "recipe":
        notification_type = "channel_recipe"
        title = f"Новый рецепт в канале {channel.name}"
        body = post_title or "Новый рецепт"
    elif post_type == "reel":
        notification_type = "channel_video"
        title = f"Новое видео в канале {channel.name}"
        body = post_title or "Новое видео"

    notifications = []
    for subscriber in subscribers:
        if getattr(subscriber, "notifications_enabled", True) is False:
            continue

        notification = Notification(
            user_id=subscriber.user_id,
            type=notification_type,
            entity_type="channel",
            entity_id=channel_id,
            actor_id=author_id,
            title=title,
            body=body,
            data={
                "channel_id": channel_id,
                "channel_name": channel.name,
                "post_id": post_id,
                "post_type": post_type,
            },
            is_read=False,
            created_at=datetime.utcnow()
        )
        notifications.append(notification)

    if notifications:
        db.bulk_save_objects(notifications)
        db.commit()
        _send_channel_push_batch(db, notifications)


def send_channel_announcement(
    db: Session,
    channel_id: int,
    announcement_text: str,
    author_id: int
):
    """Отправить объявление подписчикам канала."""
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        return

    subscribers = db.query(ChannelMember).filter(
        ChannelMember.channel_id == channel_id,
        ChannelMember.status == MEMBER_STATUS_ACTIVE,
        ChannelMember.user_id != author_id,
    ).all()

    if not subscribers:
        return

    notifications = []
    for subscriber in subscribers:
        if getattr(subscriber, "notifications_enabled", True) is False:
            continue

        notification = Notification(
            user_id=subscriber.user_id,
            type="channel_announcement",
            entity_type="channel",
            entity_id=channel_id,
            actor_id=author_id,
            title=f"Объявление от {channel.name}",
            body=announcement_text,
            data={
                "channel_id": channel_id,
                "channel_name": channel.name,
            },
            is_read=False,
            created_at=datetime.utcnow()
        )
        notifications.append(notification)

    if notifications:
        db.bulk_save_objects(notifications)
        db.commit()
        _send_channel_push_batch(db, notifications)
