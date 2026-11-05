"""Attach checklist security headers on every API response."""
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app.core.http_security import harden_set_cookie, security_headers


def _request_is_https(request: Request) -> bool:
    forwarded = (request.headers.get("x-forwarded-proto") or "").split(",")[0].strip()
    if forwarded:
        return forwarded.lower() == "https"
    return request.url.scheme == "https"


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)
        https = _request_is_https(request)
        content_type = response.headers.get("content-type")
        for name, value in security_headers(content_type=content_type, https=https).items():
            if name not in response.headers:
                response.headers[name] = value
        _harden_cookies(response, https=https)
        return response


def _harden_cookies(response: Response, *, https: bool) -> None:
    # Multiple Set-Cookie headers live in the raw list. Rewriting via
    # response.headers would collapse them into one.
    updated: list[tuple[bytes, bytes]] = []
    changed = False
    for key, value in response.raw_headers:
        if key.lower() == b"set-cookie":
            hardened = harden_set_cookie(value.decode("latin-1"), https=https)
            encoded = hardened.encode("latin-1")
            if encoded != value:
                changed = True
            updated.append((key, encoded))
        else:
            updated.append((key, value))
    if changed:
        response.raw_headers[:] = updated
