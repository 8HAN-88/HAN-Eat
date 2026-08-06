"""
TOTP 2FA helpers (Telegram-like authenticator apps).
"""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Optional

import pyotp
from jose import jwt

from app.core.config import settings
from app.models.user import User

ISSUER = "HanWe"
PENDING_TOKEN_TYPE = "2fa_pending"
PENDING_TOKEN_TTL_MINUTES = 5


def generate_secret() -> str:
    return pyotp.random_base32()


def provisioning_uri(secret: str, account_name: str) -> str:
    return pyotp.TOTP(secret).provisioning_uri(
        name=account_name or "user",
        issuer_name=ISSUER,
    )


def verify_code(secret: str, code: str) -> bool:
    if not secret or not code:
        return False
    digits = "".join(ch for ch in str(code).strip() if ch.isdigit())
    if len(digits) != 6:
        return False
    totp = pyotp.TOTP(secret)
    return bool(totp.verify(digits, valid_window=1))


def is_2fa_enabled(user: User) -> bool:
    return bool(getattr(user, "totp_enabled", False) and getattr(user, "totp_secret", None))


def create_pending_token(user_id: int) -> str:
    """Short-lived JWT after password OK, before TOTP verify."""
    expire = datetime.utcnow() + timedelta(minutes=PENDING_TOKEN_TTL_MINUTES)
    payload = {
        "sub": str(user_id),
        "type": PENDING_TOKEN_TYPE,
        "exp": expire,
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_pending_token(token: str) -> Optional[int]:
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    except Exception:
        return None
    if payload.get("type") != PENDING_TOKEN_TYPE:
        return None
    sub = payload.get("sub")
    if sub is None:
        return None
    try:
        return int(sub)
    except (TypeError, ValueError):
        return None
