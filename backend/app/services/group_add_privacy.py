"""Who may add this user to groups (Telegram Premium)."""

from __future__ import annotations

from typing import Optional

from sqlalchemy.orm import Session

from app.services.last_seen_privacy import (
    PRIVACY_CONTACTS,
    PRIVACY_EVERYBODY,
    PRIVACY_NOBODY,
    is_owner_contact,
)

ALLOWED_GROUP_ADD_PRIVACY = frozenset(
    {PRIVACY_EVERYBODY, PRIVACY_CONTACTS, PRIVACY_NOBODY}
)


def normalize_group_add_privacy(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    key = str(value).strip().lower()
    if key not in ALLOWED_GROUP_ADD_PRIVACY:
        raise ValueError("invalid_group_add_privacy")
    return key


def resolve_group_add_privacy(user) -> str:
    raw = getattr(user, "group_add_privacy", None)
    if isinstance(raw, str):
        key = raw.strip().lower()
        if key in ALLOWED_GROUP_ADD_PRIVACY:
            return key
    return PRIVACY_EVERYBODY


def can_add_user_to_group(db: Session, actor_id: int, target) -> bool:
    if int(actor_id) == int(getattr(target, "id", 0) or 0):
        return True
    privacy = resolve_group_add_privacy(target)
    if privacy == PRIVACY_EVERYBODY:
        return True
    if privacy == PRIVACY_NOBODY:
        return False
    return is_owner_contact(db, int(target.id), int(actor_id))
