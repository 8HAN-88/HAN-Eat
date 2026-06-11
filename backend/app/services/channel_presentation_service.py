"""Оформление канала и бейдж Creator."""
from __future__ import annotations

from sqlalchemy.orm import Session

from app.models.community import Channel
from app.services.subscription_service import SubscriptionService


def channel_has_creator_badge(db: Session, channel: Channel) -> bool:
    """Бейдж Creator на канале — активная подписка автора."""
    admin_id = getattr(channel, "admin_user_id", None)
    if not admin_id:
        return False
    return SubscriptionService(db).has_creator_access(int(admin_id))


def channel_presentation_fields(db: Session, channel: Channel) -> dict:
    return {
        "has_creator_badge": channel_has_creator_badge(db, channel),
        "accent_color": getattr(channel, "accent_color", None),
    }
