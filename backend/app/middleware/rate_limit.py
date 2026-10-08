"""
Глобальный rate limit по IP (Redis). Защита auth, feed, payments от злоупотреблений.
"""
from __future__ import annotations

import logging

from fastapi import Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from app.core.config import settings

logger = logging.getLogger(__name__)

_EXEMPT_PREFIXES = (
    "/health",
    "/api/v1/system/",
    "/api/v1/payments/webhook",
    "/api/v1/payments/readiness",
    "/api/v1/auth/google/readiness",
    "/api/v1/auth/open/",
    "/privacy",
    "/terms",
    "/docs",
    "/redoc",
    "/openapi.json",
)


def _is_realtime_stream(path: str) -> bool:
    """SSE — долгоживущие соединения, не считаем в минутный лимит."""
    return path.endswith("/stream") and path.startswith("/api/v1/")


def _client_ip(request: Request) -> str:
    """Client IP for rate limits.

    Prefer X-Real-IP (set by the edge to the connecting address). X-Forwarded-For
    is only used when TRUST_X_FORWARDED_FOR is on, and we take the last hop —
    the address the proxy appended — not a client-supplied first value.
    """
    real_ip = (request.headers.get("x-real-ip") or "").strip()
    if real_ip:
        return real_ip.split(",")[0].strip() or real_ip
    if getattr(settings, "TRUST_X_FORWARDED_FOR", True):
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded:
            hops = [part.strip() for part in forwarded.split(",") if part.strip()]
            if hops:
                return hops[-1]
    if request.client and request.client.host:
        return request.client.host
    return "unknown"


def _is_exempt(path: str, method: str = "GET") -> bool:
    if path == "/":
        return True
    # Public media GETs are hot; upload writes have their own per-user caps
    # and must still count toward the IP limit.
    if path.startswith("/api/v1/uploads/"):
        return method.upper() == "GET"
    return any(path.startswith(prefix) for prefix in _EXEMPT_PREFIXES)


def _is_read_heavy_get(method: str, path: str) -> bool:
    """Inbox / feed GETs are polled by the PWA and must not trip the IP cap."""
    if method != "GET":
        return False
    return (
        path.startswith("/api/v1/chats")
        or path.startswith("/api/v1/channels")
        or path.startswith("/api/v1/contacts")
        or path.startswith("/api/v1/feed")
    )


def enforce_auth_attempt_limit(request: Request, email: str | None = None) -> None:
    """Cap login/register/reset attempts per IP and per email when Redis is up."""
    if not getattr(settings, "RATE_LIMIT_ENABLED", True):
        return
    from app.core.redis_client import REDIS_IS_STUB, get_redis
    from fastapi import HTTPException

    if REDIS_IS_STUB:
        return
    redis = get_redis()
    ip = _client_ip(request)
    keys = [f"rl:auth:ip:{ip}:minute"]
    folded = (email or "").strip().lower()
    if folded:
        keys.append(f"rl:auth:email:{folded}:minute")
    ip_limit = int(getattr(settings, "AUTH_LOGIN_PER_MINUTE", 20) or 20)
    email_limit = int(getattr(settings, "AUTH_LOGIN_PER_EMAIL_PER_MINUTE", 8) or 8)
    try:
        for key in keys:
            count = redis.incr(key)
            if count == 1:
                redis.expire(key, 60)
            limit = email_limit if key.startswith("rl:auth:email:") else ip_limit
            if count > limit:
                raise HTTPException(
                    status_code=429,
                    detail="Слишком много попыток входа. Подождите минуту.",
                    headers={"Retry-After": "60"},
                )
    except HTTPException:
        raise
    except Exception as e:
        logger.warning("Auth attempt limit failed (request allowed): %s", e)


class RateLimitMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if not getattr(settings, "RATE_LIMIT_ENABLED", True):
            return await call_next(request)
        if request.method == "OPTIONS":
            return await call_next(request)
        if _is_exempt(request.url.path, request.method):
            return await call_next(request)
        if _is_realtime_stream(request.url.path):
            return await call_next(request)
        if _is_read_heavy_get(request.method, request.url.path):
            return await call_next(request)

        from app.core.redis_client import REDIS_IS_STUB, get_redis

        if REDIS_IS_STUB:
            return await call_next(request)

        redis = get_redis()
        ip = _client_ip(request)
        minute_key = f"rl:{ip}:minute"

        try:
            count = redis.incr(minute_key)
            if count == 1:
                redis.expire(minute_key, 60)
            if count > int(settings.RATE_LIMIT_PER_MINUTE):
                return JSONResponse(
                    status_code=429,
                    content={
                        "detail": "Too many requests. Please try again later.",
                        "code": "RATE_LIMIT_EXCEEDED",
                    },
                    headers={"Retry-After": "60"},
                )
        except Exception as e:
            logger.warning("Rate limit check failed (request allowed): %s", e)

        return await call_next(request)
