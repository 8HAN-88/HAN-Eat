"""Who may call a user (Telegram Premium)."""

from __future__ import annotations

from typing import Optional

from sqlalchemy.orm import Session

from app.services.last_seen_privacy import (
    PRIVACY_CONTACTS,
    PRIVACY_EVERYBODY,
    PRIVACY_NOBODY,
    is_owner_contact,
)

ALLOWED_CALL_PRIVACY = frozenset(
    {PRIVACY_EVERYBODY, PRIVACY_CONTACTS, PRIVACY_NOBODY}
)


def normalize_call_privacy(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    key = str(value).strip().lower()
    if key not in ALLOWED_CALL_PRIVACY:
        raise ValueError("invalid_call_privacy")
    return key


def resolve_call_privacy(user) -> str:
    raw = getattr(user, "call_privacy", None)
    if isinstance(raw, str):
        key = raw.strip().lower()
        if key in ALLOWED_CALL_PRIVACY:
            return key
    return PRIVACY_EVERYBODY


def can_call_user(db: Session, caller_id: int, callee) -> bool:
    if int(caller_id) == int(getattr(callee, "id", 0) or 0):
        return True
    privacy = resolve_call_privacy(callee)
    if privacy == PRIVACY_EVERYBODY:
        return True
    if privacy == PRIVACY_NOBODY:
        return False
    return is_owner_contact(db, int(callee.id), int(caller_id))
