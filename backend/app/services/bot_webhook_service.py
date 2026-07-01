"""Доставка webhook-обновлений для встроенных ботов."""
from __future__ import annotations

import hashlib
import hmac
import json
import secrets
from datetime import datetime, timezone
from typing import Any, Dict
from urllib import error as urllib_error
from urllib import request as urllib_request

from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.redis_client import REDIS_IS_STUB, get_redis
from app.models.user import User
from app.services.analytics_service import AnalyticsService

FAIL_STREAK_KEY_PREFIX = "bot:webhook:fail_streak:"
_local_fail_streaks: Dict[int, int] = {}


def _now_naive_utc() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _safe_error_text(text: str, max_len: int = 1000) -> str:
    clean = (text or "").strip()
    if len(clean) <= max_len:
        return clean
    return f"{clean[:max_len-3]}..."


def _fail_streak_key(bot_id: int) -> str:
    return f"{FAIL_STREAK_KEY_PREFIX}{int(bot_id)}"


def _clear_fail_streak(bot_id: int) -> None:
    _local_fail_streaks.pop(int(bot_id), None)
    if REDIS_IS_STUB:
        return
    try:
        get_redis().delete(_fail_streak_key(bot_id))
    except Exception:
        pass


def _increment_fail_streak(bot_id: int, ttl_seconds: int) -> int:
    if REDIS_IS_STUB:
        next_val = _local_fail_streaks.get(int(bot_id), 0) + 1
        _local_fail_streaks[int(bot_id)] = next_val
        return next_val
    try:
        redis = get_redis()
        key = _fail_streak_key(bot_id)
        next_val = int(redis.incr(key))
        redis.expire(key, max(60, int(ttl_seconds)))
        return next_val
    except Exception:
        next_val = _local_fail_streaks.get(int(bot_id), 0) + 1
        _local_fail_streaks[int(bot_id)] = next_val
        return next_val


def deliver_webhook_update(
    db: Session,
    *,
    bot_user: User,
    update_type: str,
    payload: Dict[str, Any],
    delivery_id: str | None = None,
) -> bool:
    """Отправляет update на webhook URL бота.

    Не бросает исключения: возвращает bool успеха и обновляет last_error/last_ok.
    """
    if (
        not bot_user.is_bot
        or not bot_user.bot_webhook_enabled
        or not bot_user.bot_webhook_url
    ):
        return False

    timeout = max(1.0, float(getattr(settings, "BOT_WEBHOOK_TIMEOUT_SECONDS", 4.0)))
    max_retries = max(1, int(getattr(settings, "BOT_WEBHOOK_MAX_RETRIES", 2)))
    webhook_delivery_id = (delivery_id or secrets.token_hex(12)).strip()[:64]
    body = {
        "delivery_id": webhook_delivery_id,
        "update_type": update_type,
        "update": payload,
        "timestamp": _now_naive_utc().isoformat(),
    }
    raw = json.dumps(body, ensure_ascii=False).encode("utf-8")
    timestamp_epoch = str(int(datetime.now(timezone.utc).timestamp()))
    nonce = secrets.token_hex(8)
    headers = {
        "Content-Type": "application/json; charset=utf-8",
        "User-Agent": "HANWE-BotWebhook/1.0",
        "X-HanWe-Update-Type": update_type,
        "X-HanWe-Delivery-Id": webhook_delivery_id,
        "X-HanWe-Timestamp": timestamp_epoch,
        "X-HanWe-Nonce": nonce,
    }
    if bot_user.bot_webhook_secret:
        headers["X-HanWe-Bot-Secret"] = bot_user.bot_webhook_secret
        if getattr(settings, "BOT_WEBHOOK_SIGN_WITH_SECRET", True):
            # Подпись защищает payload от подмены и помогает делать replay-check
            # на стороне webhook-приемника:
            #   expected = HMAC_SHA256(secret, "{ts}.{nonce}.{raw_body}")
            sign_input = (
                timestamp_epoch.encode("utf-8")
                + b"."
                + nonce.encode("utf-8")
                + b"."
                + raw
            )
            signature = hmac.new(
                bot_user.bot_webhook_secret.encode("utf-8"),
                sign_input,
                hashlib.sha256,
            ).hexdigest()
            headers["X-HanWe-Signature"] = signature
            headers["X-HanWe-Signature-Alg"] = "hmac-sha256"

    last_error = ""
    for attempt_idx in range(max_retries):
        req = urllib_request.Request(
            bot_user.bot_webhook_url,
            data=raw,
            headers=headers,
            method="POST",
        )
        try:
            with urllib_request.urlopen(req, timeout=timeout) as resp:
                status = getattr(resp, "status", 0) or 0
                if 200 <= int(status) < 300:
                    bot_user.bot_webhook_last_error = None
                    bot_user.bot_webhook_last_ok_at = _now_naive_utc()
                    _clear_fail_streak(bot_user.id)
                    AnalyticsService(db).log_event(
                        event_type="bot_webhook_delivery_ok",
                        entity_type="bot",
                        entity_id=bot_user.id,
                        user_id=bot_user.created_by_user_id,
                        metadata={
                            "update_type": update_type,
                            "delivery_id": webhook_delivery_id,
                            "attempts_used": attempt_idx + 1,
                        },
                    )
                    db.flush()
                    return True
                last_error = f"HTTP {status}"
        except urllib_error.HTTPError as exc:
            last_error = f"HTTP {exc.code}"
        except urllib_error.URLError as exc:
            reason = getattr(exc, "reason", exc)
            last_error = f"URL error: {reason}"
        except Exception as exc:  # noqa: BLE001
            last_error = f"Webhook delivery failed: {exc}"

    bot_user.bot_webhook_last_error = _safe_error_text(last_error or "Unknown webhook error")
    AnalyticsService(db).log_event(
        event_type="bot_webhook_delivery_fail",
        entity_type="bot",
        entity_id=bot_user.id,
        user_id=bot_user.created_by_user_id,
        metadata={
            "update_type": update_type,
            "delivery_id": webhook_delivery_id,
            "attempts_used": max_retries,
            "error": bot_user.bot_webhook_last_error,
        },
    )
    fail_ttl = max(60, int(getattr(settings, "BOT_WEBHOOK_FAIL_STREAK_TTL_SECONDS", 3600)))
    fail_streak = _increment_fail_streak(bot_user.id, fail_ttl)
    fail_threshold = max(
        0, int(getattr(settings, "BOT_WEBHOOK_AUTO_DISABLE_AFTER_FAIL_STREAK", 10))
    )
    if fail_threshold > 0 and fail_streak >= fail_threshold:
        bot_user.bot_webhook_enabled = False
        bot_user.bot_webhook_last_error = _safe_error_text(
            f"{bot_user.bot_webhook_last_error}. "
            f"Webhook auto-disabled after {fail_streak} consecutive failures."
        )
        AnalyticsService(db).log_event(
            event_type="bot_webhook_auto_disabled",
            entity_type="bot",
            entity_id=bot_user.id,
            user_id=bot_user.created_by_user_id,
            metadata={
                "fail_streak": fail_streak,
                "threshold": fail_threshold,
                "last_error": bot_user.bot_webhook_last_error,
            },
        )
        _clear_fail_streak(bot_user.id)
    db.flush()
    return False
