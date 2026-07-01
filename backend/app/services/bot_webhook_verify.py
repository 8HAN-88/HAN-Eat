"""Проверка подписи входящих bot webhook update-ов."""
from __future__ import annotations

import hashlib
import hmac
import time
from typing import Mapping, Optional

from app.core.config import settings
from app.core.redis_client import REDIS_IS_STUB, get_redis


def _first_header(headers: Mapping[str, str], key: str) -> Optional[str]:
    if key in headers:
        return headers.get(key)
    lower = key.lower()
    for k, v in headers.items():
        if k.lower() == lower:
            return v
    return None


def _nonce_key(nonce: str, timestamp: str) -> str:
    return f"bot:webhook:nonce:{timestamp}:{nonce}"


def verify_signed_webhook(
    *,
    headers: Mapping[str, str],
    raw_body: bytes,
    secret: str,
    replay_protection: bool = True,
) -> tuple[bool, str]:
    """Возвращает (ok, reason). reason='ok' при успехе.

    Ожидает подпись:
      HMAC_SHA256(secret, "{timestamp}.{nonce}.{raw_body}")
    """
    if not secret:
        return False, "missing_secret"
    timestamp = (_first_header(headers, "X-HanWe-Timestamp") or "").strip()
    nonce = (_first_header(headers, "X-HanWe-Nonce") or "").strip()
    signature = (_first_header(headers, "X-HanWe-Signature") or "").strip()
    alg = (_first_header(headers, "X-HanWe-Signature-Alg") or "").strip().lower()

    if not timestamp or not nonce or not signature:
        return False, "missing_signature_headers"
    if alg and alg != "hmac-sha256":
        return False, "unsupported_signature_alg"
    try:
        ts = int(timestamp)
    except ValueError:
        return False, "invalid_timestamp"

    now = int(time.time())
    ttl = max(30, int(getattr(settings, "BOT_WEBHOOK_SIGNATURE_TTL_SECONDS", 300)))
    if abs(now - ts) > ttl:
        return False, "timestamp_out_of_window"

    sign_input = (
        timestamp.encode("utf-8")
        + b"."
        + nonce.encode("utf-8")
        + b"."
        + raw_body
    )
    expected = hmac.new(
        secret.encode("utf-8"),
        sign_input,
        hashlib.sha256,
    ).hexdigest()
    if not hmac.compare_digest(expected, signature):
        return False, "signature_mismatch"

    if replay_protection:
        if REDIS_IS_STUB:
            return True, "ok_no_redis"
        key = _nonce_key(nonce, timestamp)
        # set nx: если nonce уже был — replay
        created = bool(get_redis().set(key, "1", ex=ttl, nx=True))
        if not created:
            return False, "replay_detected"
    return True, "ok"
