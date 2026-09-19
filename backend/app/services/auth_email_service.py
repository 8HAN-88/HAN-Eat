"""Коды и письма: подтверждение почты, сброс пароля, смена почты.

Новые письма — 6-значный OTP (как у Apple / Google / банков).
Старые длинные ссылки из уже отправленных писем по-прежнему принимаются.
"""
from __future__ import annotations

import hashlib
import json
import logging
import re
import secrets
from datetime import datetime, timedelta
from typing import Optional, Tuple

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.auth_token import (
    PURPOSE_CHANGE_EMAIL,
    PURPOSE_RESET_PASSWORD,
    PURPOSE_VERIFY_EMAIL,
    AuthToken,
)
from app.models.user import User
from app.services.auth_link_redirect import email_web_link
from app.services.email_delivery_service import (
    send_transactional_email,
    send_transactional_email_or_raise,
)
from app.services.email_templates import render_branded_email

logger = logging.getLogger(__name__)

OTP_LENGTH = 6
_OTP_RE = re.compile(r"^\d{6}$")
_LEGACY_MIN_LEN = 16

ERR_INVALID = "Неверный код"
ERR_USED = "Этот код уже использован"
ERR_EXPIRED = "Код устарел. Запросите новый"
ERR_LOCKED = "Слишком много попыток. Запросите новый код"
ERR_NEED_EMAIL = "Укажите почту и код"


def is_email_verified(user: User) -> bool:
    return user.email_verified_at is not None


def mark_email_verified(user: User) -> None:
    user.email_verified_at = datetime.utcnow()


def normalize_auth_code(raw: str) -> str:
    """Для 6 цифр убираем пробелы и дефисы. Длинный токен не трогаем:
    `token_urlsafe` часто содержит `-`, его нельзя вырезать."""
    trimmed = (raw or "").strip()
    compact = "".join(ch for ch in trimmed if not ch.isspace() and ch != "-")
    if _OTP_RE.fullmatch(compact):
        return compact
    return trimmed


def is_otp_code(raw: str) -> bool:
    return bool(_OTP_RE.fullmatch(normalize_auth_code(raw)))


def _hash_token(raw: str) -> str:
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _generate_otp() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def _parse_extra(raw: Optional[str]) -> dict:
    if not raw:
        return {}
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def _dump_extra(extra: dict) -> str:
    return json.dumps(extra, ensure_ascii=False)


def _otp_minutes() -> int:
    minutes = int(getattr(settings, "AUTH_OTP_MINUTES", 15) or 15)
    return max(5, min(minutes, 60))


def _max_attempts() -> int:
    n = int(getattr(settings, "AUTH_OTP_MAX_ATTEMPTS", 5) or 5)
    return max(3, min(n, 10))


def _resend_seconds() -> int:
    n = int(getattr(settings, "AUTH_OTP_RESEND_SECONDS", 45) or 45)
    return max(15, min(n, 180))


def _invalidate_active_tokens(db: Session, user_id: int, purpose: str) -> None:
    now = datetime.utcnow()
    rows = (
        db.query(AuthToken)
        .filter(
            AuthToken.user_id == user_id,
            AuthToken.purpose == purpose,
            AuthToken.used_at.is_(None),
            AuthToken.expires_at > now,
        )
        .all()
    )
    for row in rows:
        row.used_at = now


def _latest_unused_token(
    db: Session, user_id: int, purpose: str
) -> Optional[AuthToken]:
    now = datetime.utcnow()
    return (
        db.query(AuthToken)
        .filter(
            AuthToken.user_id == user_id,
            AuthToken.purpose == purpose,
            AuthToken.used_at.is_(None),
            AuthToken.expires_at > now,
        )
        .order_by(AuthToken.id.desc())
        .first()
    )


def recently_sent_otp(db: Session, user_id: int, purpose: str) -> bool:
    row = _latest_unused_token(db, user_id, purpose)
    if row is None or row.created_at is None:
        return False
    age = (datetime.utcnow() - row.created_at).total_seconds()
    return age < _resend_seconds()


def create_auth_otp(
    db: Session,
    user_id: int,
    purpose: str,
    extra_data: Optional[dict] = None,
) -> str:
    """Создаёт одноразовый 6-значный код. Предыдущие активные коды гасятся."""
    _invalidate_active_tokens(db, user_id, purpose)
    extra = dict(extra_data or {})
    extra.setdefault("attempts", 0)
    extra["kind"] = "otp"
    nonce = secrets.token_hex(16)
    extra["otp_nonce"] = nonce
    raw = _generate_otp()
    # nonce делает hash уникальным даже при повторе цифр у того же пользователя
    token_hash = _hash_token(f"{user_id}:{purpose}:{raw}:{nonce}")
    now = datetime.utcnow()
    row = AuthToken(
        user_id=user_id,
        purpose=purpose,
        token_hash=token_hash,
        extra_data=_dump_extra(extra),
        expires_at=now + timedelta(minutes=_otp_minutes()),
        created_at=now,
    )
    db.add(row)
    db.flush()
    return raw


def _generate_raw_token() -> str:
    """Только для тестов совместимости со старыми письмами."""
    return secrets.token_urlsafe(32)


def create_legacy_auth_token(
    db: Session,
    user_id: int,
    purpose: str,
    hours_valid: int,
    extra_data: Optional[dict] = None,
) -> str:
    """Длинный токен — чтобы уже отправленные ссылки и тесты не сломались."""
    _invalidate_active_tokens(db, user_id, purpose)
    raw = _generate_raw_token()
    row = AuthToken(
        user_id=user_id,
        purpose=purpose,
        token_hash=_hash_token(raw),
        extra_data=json.dumps(extra_data) if extra_data else None,
        expires_at=datetime.utcnow() + timedelta(hours=hours_valid),
        created_at=datetime.utcnow(),
    )
    db.add(row)
    db.flush()
    return raw


def _find_user_by_email(db: Session, email: str) -> Optional[User]:
    email_norm = (email or "").strip().lower()
    if not email_norm:
        return None
    user = (
        db.query(User)
        .filter(func.lower(User.email) == email_norm, User.deleted_at.is_(None))
        .first()
    )
    return user


def _resolve_otp_user(db: Session, email: Optional[str], purpose: str) -> Optional[User]:
    email_norm = (email or "").strip().lower()
    if not email_norm:
        return None
    user = _find_user_by_email(db, email_norm)
    if user:
        return user
    if purpose != PURPOSE_CHANGE_EMAIL:
        return None
    now = datetime.utcnow()
    rows = (
        db.query(AuthToken)
        .filter(
            AuthToken.purpose == purpose,
            AuthToken.used_at.is_(None),
            AuthToken.expires_at > now,
        )
        .all()
    )
    for row in rows:
        extra = _parse_extra(row.extra_data)
        if (extra.get("new_email") or "").strip().lower() == email_norm:
            return db.query(User).filter(User.id == row.user_id).first()
    return None


def _otp_expected_hash(user_id: int, purpose: str, code: str, nonce: Optional[str]) -> str:
    if nonce:
        return _hash_token(f"{user_id}:{purpose}:{code}:{nonce}")
    return _hash_token(f"{user_id}:{purpose}:{code}")


def _bump_attempts(row: AuthToken) -> Tuple[int, bool]:
    extra = _parse_extra(row.extra_data)
    attempts = int(extra.get("attempts") or 0) + 1
    extra["attempts"] = attempts
    row.extra_data = _dump_extra(extra)
    locked = attempts >= _max_attempts()
    if locked:
        row.used_at = datetime.utcnow()
    return attempts, locked


def consume_token(
    db: Session,
    raw_token: str,
    purpose: str,
    email: Optional[str] = None,
) -> Tuple[Optional[AuthToken], Optional[str]]:
    """Возвращает (token_row, error_message)."""
    raw = normalize_auth_code(raw_token)
    if not raw:
        return None, ERR_INVALID

    if is_otp_code(raw):
        user = _resolve_otp_user(db, email, purpose)
        if user is None:
            # Без почты короткий код не ищем — иначе 1e6 вариантов на всю базу.
            if not (email or "").strip():
                return None, ERR_NEED_EMAIL
            return None, ERR_INVALID
        row = _latest_unused_token(db, user.id, purpose)
        if row is None:
            return None, ERR_INVALID
        if row.expires_at < datetime.utcnow():
            return None, ERR_EXPIRED
        extra = _parse_extra(row.extra_data)
        if int(extra.get("attempts") or 0) >= _max_attempts():
            return None, ERR_LOCKED
        expected = _otp_expected_hash(
            user.id, purpose, raw, extra.get("otp_nonce")
        )
        if row.token_hash != expected:
            _, locked = _bump_attempts(row)
            return None, ERR_LOCKED if locked else ERR_INVALID
        row.used_at = datetime.utcnow()
        return row, None

    if len(raw) < _LEGACY_MIN_LEN:
        return None, ERR_INVALID

    row = (
        db.query(AuthToken)
        .filter(
            AuthToken.token_hash == _hash_token(raw),
            AuthToken.purpose == purpose,
        )
        .first()
    )
    if not row:
        return None, ERR_INVALID
    if row.used_at is not None:
        return None, ERR_USED
    if row.expires_at < datetime.utcnow():
        return None, ERR_EXPIRED
    row.used_at = datetime.utcnow()
    return row, None


def _otp_expiry_note() -> str:
    return f"Код действует {_otp_minutes()} мин."


def send_verify_email(db: Session, user: User) -> None:
    if recently_sent_otp(db, user.id, PURPOSE_VERIFY_EMAIL):
        logger.info("verify email skipped, cooldown user_id=%s", user.id)
        return
    raw = create_auth_otp(db, user.id, PURPOSE_VERIFY_EMAIL)
    link = email_web_link("verify-email", raw, email=user.email)
    subject = "Код подтверждения — HanWe"
    try:
        text, html = render_branded_email(
            preheader=f"Код HanWe: {raw[:3]} {raw[3:]}",
            title="Подтвердите почту",
            greeting=f"Здравствуйте, {user.name}!",
            paragraphs=[
                "Введите этот код в приложении HanWe, чтобы подтвердить почту.",
            ],
            cta_label="Открыть приложение",
            cta_url=link,
            otp_code=raw,
            expiry_note=_otp_expiry_note(),
        )
        send_transactional_email_or_raise(user.email, subject, text, html)
    except Exception:
        _invalidate_active_tokens(db, user.id, PURPOSE_VERIFY_EMAIL)
        raise


def send_password_reset_email(db: Session, user: User) -> bool:
    if recently_sent_otp(db, user.id, PURPOSE_RESET_PASSWORD):
        logger.info("reset email skipped, cooldown user_id=%s", user.id)
        return True
    raw = create_auth_otp(db, user.id, PURPOSE_RESET_PASSWORD)
    link = email_web_link("reset-password", raw, email=user.email)
    subject = "Код для нового пароля — HanWe"
    display_name = (user.name or "").strip() or "друг"
    try:
        text, html = render_branded_email(
            preheader=f"Код HanWe: {raw[:3]} {raw[3:]}",
            title="Сброс пароля",
            greeting=f"Здравствуйте, {display_name}!",
            paragraphs=[
                "Введите этот код в приложении HanWe, затем задайте новый пароль.",
            ],
            cta_label="Открыть приложение",
            cta_url=link,
            otp_code=raw,
            expiry_note=_otp_expiry_note(),
            security_note=(
                "Если вы не запрашивали сброс пароля, проигнорируйте это письмо. "
                "Ваш текущий пароль останется без изменений."
            ),
        )
        sent = send_transactional_email(user.email, subject, text, html)
        if not sent:
            _invalidate_active_tokens(db, user.id, PURPOSE_RESET_PASSWORD)
        return sent
    except Exception:
        _invalidate_active_tokens(db, user.id, PURPOSE_RESET_PASSWORD)
        raise


def send_change_email_confirmation(db: Session, user: User, new_email: str) -> bool:
    if recently_sent_otp(db, user.id, PURPOSE_CHANGE_EMAIL):
        logger.info("change-email skipped, cooldown user_id=%s", user.id)
        return True
    raw = create_auth_otp(
        db,
        user.id,
        PURPOSE_CHANGE_EMAIL,
        extra_data={"new_email": new_email},
    )
    link = email_web_link("confirm-email-change", raw, email=new_email)
    subject = "Код для новой почты — HanWe"
    try:
        text, html = render_branded_email(
            preheader=f"Код HanWe: {raw[:3]} {raw[3:]}",
            title="Подтвердите новую почту",
            greeting=None,
            paragraphs=[
                f"Вы запросили смену почты на {new_email}.",
                "Введите этот код в приложении HanWe.",
            ],
            cta_label="Открыть приложение",
            cta_url=link,
            otp_code=raw,
            expiry_note=_otp_expiry_note(),
        )
        sent = send_transactional_email(new_email, subject, text, html)
        if not sent:
            _invalidate_active_tokens(db, user.id, PURPOSE_CHANGE_EMAIL)
        return sent
    except Exception:
        _invalidate_active_tokens(db, user.id, PURPOSE_CHANGE_EMAIL)
        raise
