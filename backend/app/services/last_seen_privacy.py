"""Telegram-like last-seen visibility: everybody / contacts / nobody."""

from __future__ import annotations

from typing import Optional

from sqlalchemy.orm import Session

from app.models.conversation import Contact

PRIVACY_EVERYBODY = "everybody"
PRIVACY_CONTACTS = "contacts"
PRIVACY_NOBODY = "nobody"
ALLOWED_LAST_SEEN_PRIVACY = frozenset(
    {PRIVACY_EVERYBODY, PRIVACY_CONTACTS, PRIVACY_NOBODY}
)


def normalize_last_seen_privacy(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    key = str(value).strip().lower()
    if key not in ALLOWED_LAST_SEEN_PRIVACY:
        raise ValueError("invalid_last_seen_privacy")
    return key


def resolve_last_seen_privacy(user) -> str:
    raw = getattr(user, "last_seen_privacy", None)
    if isinstance(raw, str):
        key = raw.strip().lower()
        if key in ALLOWED_LAST_SEEN_PRIVACY:
            return key
    return (
        PRIVACY_EVERYBODY
        if bool(getattr(user, "show_last_seen", True))
        else PRIVACY_NOBODY
    )


def sync_show_last_seen_flag(user, privacy: str) -> None:
    """Keep legacy show_last_seen bool aligned with the tier."""
    user.show_last_seen = privacy != PRIVACY_NOBODY


def apply_last_seen_privacy_update(
    user,
    *,
    last_seen_privacy: Optional[str] = None,
    show_last_seen: Optional[bool] = None,
) -> str:
    """
    Apply privacy update. Explicit last_seen_privacy wins over show_last_seen.
    Returns the resolved privacy string.
    """
    if last_seen_privacy is not None:
        privacy = normalize_last_seen_privacy(last_seen_privacy)
        assert privacy is not None
    elif show_last_seen is not None:
        privacy = PRIVACY_EVERYBODY if show_last_seen else PRIVACY_NOBODY
    else:
        return resolve_last_seen_privacy(user)

    user.last_seen_privacy = privacy
    sync_show_last_seen_flag(user, privacy)
    return privacy


def is_owner_contact(db: Session, owner_id: int, other_id: int) -> bool:
    if owner_id == other_id:
        return True
    row = (
        db.query(Contact.id)
        .filter(
            Contact.owner_user_id == int(owner_id),
            Contact.contact_user_id == int(other_id),
        )
        .first()
    )
    return row is not None


def _viewer_has_privacy_plus(db: Optional[Session], viewer_id: Optional[int]) -> bool:
    if db is None or viewer_id is None:
        return False
    try:
        from app.services.subscription_service import SubscriptionService

        return SubscriptionService(db).has_feature(int(viewer_id), "privacy_plus")
    except Exception:
        return False


def can_viewer_see_last_seen(
    db: Optional[Session],
    owner,
    viewer_id: Optional[int],
) -> bool:
    if viewer_id is not None and int(viewer_id) == int(owner.id):
        return True
    privacy = resolve_last_seen_privacy(owner)
    if privacy == PRIVACY_EVERYBODY:
        allowed = True
    elif privacy == PRIVACY_NOBODY:
        allowed = False
    elif db is None or viewer_id is None:
        allowed = False
    else:
        allowed = is_owner_contact(db, int(owner.id), int(viewer_id))
    if not allowed:
        return False
    if db is None or viewer_id is None:
        return True
    from app.models.user import User

    viewer = db.query(User).filter(User.id == int(viewer_id)).first()
    if viewer is None:
        return True
    if resolve_last_seen_privacy(viewer) != PRIVACY_NOBODY:
        return True
    return _viewer_has_privacy_plus(db, viewer_id)
