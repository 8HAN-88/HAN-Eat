"""Who may send voice / video notes to a user (Telegram Premium)."""

from __future__ import annotations

from typing import Optional

from sqlalchemy.orm import Session

from app.services.last_seen_privacy import (
    PRIVACY_CONTACTS,
    PRIVACY_EVERYBODY,
    PRIVACY_NOBODY,
    is_owner_contact,
)

ALLOWED_VOICE_PRIVACY = frozenset(
    {PRIVACY_EVERYBODY, PRIVACY_CONTACTS, PRIVACY_NOBODY}
)


def normalize_voice_privacy(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    key = str(value).strip().lower()
    if key not in ALLOWED_VOICE_PRIVACY:
        raise ValueError("invalid_voice_privacy")
    return key


def resolve_voice_privacy(user) -> str:
    raw = getattr(user, "voice_privacy", None)
    if isinstance(raw, str):
        key = raw.strip().lower()
        if key in ALLOWED_VOICE_PRIVACY:
            return key
    return PRIVACY_EVERYBODY


def can_send_voice_to(db: Session, sender_id: int, recipient) -> bool:
    if int(sender_id) == int(getattr(recipient, "id", 0) or 0):
        return True
    privacy = resolve_voice_privacy(recipient)
    if privacy == PRIVACY_EVERYBODY:
        return True
    if privacy == PRIVACY_NOBODY:
        return False
    return is_owner_contact(db, int(recipient.id), int(sender_id))
