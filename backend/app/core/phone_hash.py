"""Нормализация телефона и хеш для поиска друзей (как в Telegram — без хранения сырого номера)."""
from __future__ import annotations

import hashlib
import re

from app.core.config import settings

_DIGITS = re.compile(r"\D+")


def normalize_phone_e164(raw: str, default_region: str = "RU") -> str | None:
    """Приводит номер к E.164 (+7...) или None."""
    if not raw or not str(raw).strip():
        return None
    digits = _DIGITS.sub("", str(raw).strip())
    if not digits:
        return None
    if digits.startswith("00"):
        digits = digits[2:]
    region = (default_region or "RU").upper()
    if region == "RU":
        if len(digits) == 11 and digits.startswith("8"):
            digits = "7" + digits[1:]
        if len(digits) == 11 and digits.startswith("7"):
            return f"+{digits}"
        if len(digits) == 10:
            return f"+7{digits}"
    if len(digits) >= 10 and len(digits) <= 15:
        return f"+{digits}"
    return None


def hash_phone_e164(e164: str) -> str:
    pepper = settings.PHONE_HASH_PEPPER
    payload = f"{pepper}:{e164}".encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def hash_phone_raw(raw: str, default_region: str = "RU") -> str | None:
    e164 = normalize_phone_e164(raw, default_region=default_region)
    if not e164:
        return None
    return hash_phone_e164(e164)
