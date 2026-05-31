"""
Участники канала: active (полный доступ) vs pending (заявка в приватный канал).
"""
from __future__ import annotations

from typing import Optional, Tuple

from sqlalchemy.orm import Session

from app.models.community import Channel
from app.models.community_member import ChannelMember
from app.models.user import User

MEMBER_STATUS_ACTIVE = "active"
MEMBER_STATUS_PENDING = "pending"
MEMBER_STATUS_REJECTED = "rejected"

STAFF_ROLES = frozenset({"owner", "admin", "moderator"})


def get_membership(
    db: Session, channel_id: int, user_id: int
) -> Optional[ChannelMember]:
    return (
        db.query(ChannelMember)
        .filter(
            ChannelMember.channel_id == channel_id,
            ChannelMember.user_id == user_id,
        )
        .first()
    )


def is_channel_owner(channel: Channel, user: Optional[User]) -> bool:
    return bool(user and channel.admin_user_id == user.id)


def is_staff_member(member: Optional[ChannelMember], channel: Channel, user: Optional[User]) -> bool:
    if is_channel_owner(channel, user):
        return True
    if not member or member.status != MEMBER_STATUS_ACTIVE:
        return False
    return member.role in STAFF_ROLES


def is_active_member(member: Optional[ChannelMember], channel: Channel, user: Optional[User]) -> bool:
    if is_channel_owner(channel, user):
        return True
    return member is not None and member.status == MEMBER_STATUS_ACTIVE


def can_view_channel_posts(channel: Channel, user: Optional[User], member: Optional[ChannelMember]) -> bool:
    if channel.is_public:
        return True
    return is_active_member(member, channel, user)


def can_preview_channel(channel: Channel, user: Optional[User]) -> bool:
    """Карточка канала в поиске / по ссылке — без постов для неактивных."""
    if channel.is_public:
        return True
    return user is not None


def membership_status_for_user(
    member: Optional[ChannelMember], channel: Channel, user: Optional[User]
) -> str:
    if not user:
        return "none"
    if is_active_member(member, channel, user):
        return MEMBER_STATUS_ACTIVE
    if member and member.status == MEMBER_STATUS_PENDING:
        return MEMBER_STATUS_PENDING
    return "none"


def count_active_members(db: Session, channel_id: int) -> int:
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        return 0
    return (
        db.query(ChannelMember)
        .filter(
            ChannelMember.channel_id == channel_id,
            ChannelMember.status == MEMBER_STATUS_ACTIVE,
        )
        .count()
    )


def sync_channel_members_count(db: Session, channel_id: int) -> int:
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        return 0
    total = count_active_members(db, channel_id)
    channel.members_count = total
    return total


def active_member_channel_ids_subquery(db: Session, user_id: int):
    return (
        db.query(ChannelMember.channel_id)
        .filter(
            ChannelMember.user_id == user_id,
            ChannelMember.status == MEMBER_STATUS_ACTIVE,
        )
        .subquery()
    )
