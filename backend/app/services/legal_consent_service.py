"""Согласие с политикой конфиденциальности и пользовательским соглашением."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.user import User


def current_legal_version() -> str:
    return (settings.LEGAL_DOCUMENT_VERSION or "2026-06-03").strip()


def consent_required(user: User | None) -> bool:
    if user is None:
        return True
    version = current_legal_version()
    if not user.legal_consent_at:
        return True
    accepted = (user.legal_consent_version or "").strip()
    return accepted != version


def record_consent(user: User, db: Session) -> User:
    user.legal_consent_version = current_legal_version()
    user.legal_consent_at = datetime.utcnow()
    db.add(user)
    db.flush()
    return user


def legal_status_payload() -> Dict[str, Any]:
    base = (settings.API_PUBLIC_BASE_URL or settings.FRONTEND_URL or "").rstrip("/")
    return {
        "version": current_legal_version(),
        "privacy_url": f"{base}/privacy" if base else "https://api.haneat.app/privacy",
        "terms_url": f"{base}/terms" if base else "https://api.haneat.app/terms",
        "documents": [
            {
                "id": "privacy",
                "title": "Политика конфиденциальности",
            },
            {
                "id": "terms",
                "title": "Пользовательское соглашение",
            },
        ],
        "consent_text": (
            "Я подтверждаю, что ознакомился(ась) с Политикой конфиденциальности "
            "и Пользовательским соглашением, даю согласие на обработку персональных "
            "данных в соответствии с Федеральным законом № 152-ФЗ и принимаю "
            "условия использования сервиса HAN Eat."
        ),
    }


def user_legal_fields(user: User) -> Dict[str, Any]:
    return {
        "legal_consent_required": consent_required(user),
        "legal_consent_version": user.legal_consent_version,
        "legal_consent_at": (
            user.legal_consent_at.isoformat() if user.legal_consent_at else None
        ),
    }
