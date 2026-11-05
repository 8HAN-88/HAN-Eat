"""Response headers and cookie flags from the public security checklist.

Session auth is a Bearer JWT, not a cookie, so a foreign site cannot attach
the token with a form post. If a cookie is set anyway, it must be HttpOnly,
SameSite, and Secure on HTTPS.
"""
from __future__ import annotations

API_CONTENT_SECURITY_POLICY = (
    "default-src 'none'; frame-ancestors 'none'; base-uri 'none'"
)

# Flutter web needs inline bootstrap and wasm workers. The policy still
# blocks plugins, foreign framing, and base-tag hijacks.
WEB_CONTENT_SECURITY_POLICY = (
    "default-src 'self'; "
    "script-src 'self' 'unsafe-inline' 'unsafe-eval' blob:; "
    "style-src 'self' 'unsafe-inline'; "
    "img-src 'self' data: blob: https:; "
    "media-src 'self' blob: https: mediastream:; "
    "font-src 'self' data:; "
    "connect-src 'self' https: wss:; "
    "worker-src 'self' blob:; "
    "frame-src 'self' https:; "
    "object-src 'none'; "
    "base-uri 'self'; "
    "form-action 'self'; "
    "frame-ancestors 'self'"
)

HSTS_VALUE = "max-age=15552000"
REFERRER_POLICY = "strict-origin-when-cross-origin"
API_PERMISSIONS_POLICY = "camera=(), microphone=(), geolocation=(), payment=()"


def content_security_policy_for(content_type: str | None) -> str:
    if content_type and "text/html" in content_type.lower():
        return WEB_CONTENT_SECURITY_POLICY
    return API_CONTENT_SECURITY_POLICY


def security_headers(*, content_type: str | None, https: bool) -> dict[str, str]:
    headers = {
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
        "Referrer-Policy": REFERRER_POLICY,
        "Permissions-Policy": API_PERMISSIONS_POLICY,
        "Content-Security-Policy": content_security_policy_for(content_type),
    }
    if https:
        headers["Strict-Transport-Security"] = HSTS_VALUE
    return headers


def harden_set_cookie(value: str, *, https: bool) -> str:
    """Add missing cookie flags. Do not downgrade flags the app already set."""
    lowered = value.lower()
    parts = [value]
    if "httponly" not in lowered:
        parts.append("HttpOnly")
    if "samesite=" not in lowered:
        parts.append("SameSite=Lax")
    if https and "secure" not in lowered:
        parts.append("Secure")
    if len(parts) == 1:
        return value
    return "; ".join(parts)


def database_url_is_open_default(url: str | None) -> bool:
    """The sample URL ships in code and must not be the production database."""
    value = (url or "").strip().lower()
    if not value:
        return True
    if value.startswith("sqlite"):
        return True
    return "://user:password@" in value or "://user:password:" in value
