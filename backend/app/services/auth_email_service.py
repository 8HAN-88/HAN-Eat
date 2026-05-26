"""Токены и письма: подтверждение email, сброс/смена пароля, смена email."""
from __future__ import annotations

import hashlib
import json
import logging
import secrets
from datetime import datetime, timedelta
from typing import Optional, Tuple
from urllib.parse import quote

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.auth_token import (
    PURPOSE_CHANGE_EMAIL,
    PURPOSE_RESET_PASSWORD,
    PURPOSE_VERIFY_EMAIL,
    AuthToken,
)
from app.models.user import User
from app.services.email_delivery_service import send_transactional_email
from app.services.email_templates import render_branded_email

logger = logging.getLogger(__name__)


def is_email_verified(user: User) -> bool:
    return user.email_verified_at is not None


def mark_email_verified(user: User) -> None:
    user.email_verified_at = datetime.utcnow()


def _hash_token(raw: str) -> str:
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _generate_raw_token() -> str:
    return secrets.token_urlsafe(32)


def _verify_link(purpose: str, raw_token: str) -> str:
    base = settings.AUTH_LINK_BASE_URL.rstrip("/")
    return f"{base}/{purpose}?token={quote(raw_token, safe='')}"


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


def _create_token(
    db: Session,
    user_id: int,
    purpose: str,
    hours_valid: int,
    extra_data: Optional[dict] = None,
) -> str:
    _invalidate_active_tokens(db, user_id, purpose)
    raw = _generate_raw_token()
    row = AuthToken(
        user_id=user_id,
        purpose=purpose,
        token_hash=_hash_token(raw),
        extra_data=json.dumps(extra_data) if extra_data else None,
        expires_at=datetime.utcnow() + timedelta(hours=hours_valid),
    )
    db.add(row)
    db.flush()
    return raw


def send_verify_email(db: Session, user: User) -> bool:
    raw = _create_token(
        db,
        user.id,
        PURPOSE_VERIFY_EMAIL,
        settings.AUTH_VERIFY_EMAIL_HOURS,
    )
    link = _verify_link("verify-email", raw)
    subject = "Подтвердите email — HAN Eat"
    text, html = render_branded_email(
        preheader="Подтвердите email, чтобы войти в HAN Eat",
        title="Подтвердите ваш email",
        greeting=f"Здравствуйте, {user.name}!",
        paragraphs=[
            "Спасибо за регистрацию в HAN Eat. Нажмите кнопку ниже, "
            "чтобы подтвердить адрес почты и завершить создание аккаунта.",
        ],
        cta_label="Подтвердить email",
        cta_url=link,
        expiry_note=f"Ссылка действует {settings.AUTH_VERIFY_EMAIL_HOURS} ч.",
    )
    return send_transactional_email(user.email, subject, text, html)


def send_password_reset_email(db: Session, user: User) -> bool:
    raw = _create_token(
        db,
        user.id,
        PURPOSE_RESET_PASSWORD,
        settings.AUTH_RESET_PASSWORD_HOURS,
    )
    link = _verify_link("reset-password", raw)
    subject = "Сброс пароля — HAN Eat"
    display_name = (user.name or "").strip() or "друг"
    text, html = render_branded_email(
        preheader="Запрос на сброс пароля в HAN Eat",
        title="Сброс пароля",
        greeting=f"Здравствуйте, {display_name}!",
        paragraphs=[
            "Мы получили запрос на сброс пароля для вашего аккаунта HAN Eat.",
            "Нажмите кнопку ниже на этом телефоне — откроется приложение, "
            "где вы сможете задать новый пароль.",
        ],
        cta_label="Задать новый пароль",
        cta_url=link,
        expiry_note=f"Ссылка действует {settings.AUTH_RESET_PASSWORD_HOURS} ч.",
        security_note=(
            "Если вы не запрашивали сброс пароля, проигнорируйте это письмо. "
            "Ваш текущий пароль останется без изменений."
        ),
    )
    return send_transactional_email(user.email, subject, text, html)


def send_change_email_confirmation(db: Session, user: User, new_email: str) -> bool:
    raw = _create_token(
        db,
        user.id,
        PURPOSE_CHANGE_EMAIL,
        settings.AUTH_CHANGE_EMAIL_HOURS,
        extra_data={"new_email": new_email},
    )
    link = _verify_link("confirm-email-change", raw)
    subject = "Подтвердите новый email — HAN Eat"
    text, html = render_branded_email(
        preheader="Подтвердите смену email в HAN Eat",
        title="Подтвердите новый email",
        greeting=None,
        paragraphs=[
            f"Вы запросили смену email на {new_email}.",
            "Нажмите кнопку ниже, чтобы подтвердить новый адрес.",
        ],
        cta_label="Подтвердить email",
        cta_url=link,
        expiry_note=f"Ссылка действует {settings.AUTH_CHANGE_EMAIL_HOURS} ч.",
    )
    return send_transactional_email(new_email, subject, text, html)


def consume_token(
    db: Session, raw_token: str, purpose: str
) -> Tuple[Optional[AuthToken], Optional[str]]:
    """Возвращает (token_row, error_message)."""
    if not raw_token or len(raw_token) < 16:
        return None, "Invalid token"
    row = (
        db.query(AuthToken)
        .filter(
            AuthToken.token_hash == _hash_token(raw_token),
            AuthToken.purpose == purpose,
        )
        .first()
    )
    if not row:
        return None, "Invalid or expired token"
    if row.used_at is not None:
        return None, "Token already used"
    if row.expires_at < datetime.utcnow():
        return None, "Token expired"
    row.used_at = datetime.utcnow()
    return row, None
