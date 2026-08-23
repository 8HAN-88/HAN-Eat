"""Create / list / revoke auth sessions (refresh-token binding)."""
from __future__ import annotations

import secrets
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.core.security import create_access_token, create_refresh_token
from app.models.auth_session import AuthSession
from app.models.user import User


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _new_jti() -> str:
    return secrets.token_hex(16)


def create_session(
    db: Session,
    *,
    user: User,
    device_name: Optional[str] = None,
    device_platform: Optional[str] = None,
    user_agent: Optional[str] = None,
    ip_address: Optional[str] = None,
) -> tuple[str, str, AuthSession]:
    from app.services.emoji_pack_service import strip_custom_emoji_tokens

    jti = _new_jti()
    session = AuthSession(
        user_id=user.id,
        jti=jti,
        device_name=strip_custom_emoji_tokens(device_name)[:120] or None,
        device_platform=(device_platform or "").strip()[:40] or None,
        user_agent=(user_agent or "").strip()[:512] or None,
        ip_address=(ip_address or "").strip()[:64] or None,
        created_at=_now(),
        last_seen_at=_now(),
    )
    db.add(session)
    db.flush()
    access = create_access_token(data={"sub": str(user.id)})
    refresh = create_refresh_token(
        data={"sub": str(user.id), "sid": session.id, "jti": jti}
    )
    return access, refresh, session


def rotate_session_tokens(
    db: Session,
    *,
    session: AuthSession,
    user: User,
) -> tuple[str, str]:
    jti = _new_jti()
    session.jti = jti
    session.last_seen_at = _now()
    db.flush()
    access = create_access_token(data={"sub": str(user.id)})
    refresh = create_refresh_token(
        data={"sub": str(user.id), "sid": session.id, "jti": jti}
    )
    return access, refresh


def get_active_session(
    db: Session, *, session_id: int, jti: Optional[str]
) -> Optional[AuthSession]:
    row = (
        db.query(AuthSession)
        .filter(
            AuthSession.id == session_id,
            AuthSession.revoked_at.is_(None),
        )
        .first()
    )
    if row is None:
        return None
    if jti and row.jti != jti:
        return None
    return row


def list_sessions(db: Session, *, user_id: int) -> list[AuthSession]:
    return (
        db.query(AuthSession)
        .filter(
            AuthSession.user_id == user_id,
            AuthSession.revoked_at.is_(None),
        )
        .order_by(AuthSession.last_seen_at.desc())
        .all()
    )


def revoke_session(
    db: Session, *, user_id: int, session_id: int
) -> Optional[AuthSession]:
    row = (
        db.query(AuthSession)
        .filter(
            AuthSession.id == session_id,
            AuthSession.user_id == user_id,
            AuthSession.revoked_at.is_(None),
        )
        .first()
    )
    if row is None:
        return None
    row.revoked_at = _now()
    return row


def revoke_other_sessions(
    db: Session, *, user_id: int, keep_session_id: int
) -> int:
    now = _now()
    q = (
        db.query(AuthSession)
        .filter(
            AuthSession.user_id == user_id,
            AuthSession.revoked_at.is_(None),
            AuthSession.id != keep_session_id,
        )
    )
    count = 0
    for row in q.all():
        row.revoked_at = now
        count += 1
    return count


def revoke_all_sessions(db: Session, *, user_id: int) -> int:
    now = _now()
    count = 0
    for row in (
        db.query(AuthSession)
        .filter(
            AuthSession.user_id == user_id,
            AuthSession.revoked_at.is_(None),
        )
        .all()
    ):
        row.revoked_at = now
        count += 1
    return count
