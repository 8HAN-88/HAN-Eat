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
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    if request.client and request.client.host:
        return request.client.host
    return "unknown"


def _is_exempt(path: str) -> bool:
    if path == "/":
        return True
    if path.startswith("/api/v1/uploads/"):
        return True
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


class RateLimitMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if not getattr(settings, "RATE_LIMIT_ENABLED", True):
            return await call_next(request)
        if request.method == "OPTIONS":
            return await call_next(request)
        if _is_exempt(request.url.path):
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
