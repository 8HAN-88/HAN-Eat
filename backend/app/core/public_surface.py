"""What the public HTTP surface may advertise."""
from __future__ import annotations

from urllib.parse import urlparse


_PRODUCTION_WEB_ORIGINS = (
    "https://haneat.app",
    "https://www.haneat.app",
    "https://kitchen.haneat.app",
)


def docs_routes_for_env(app_env: str) -> dict[str, str | None]:
    """Swagger / OpenAPI stay off outside development."""
    if app_env == "development":
        return {
            "docs_url": "/docs",
            "redoc_url": "/redoc",
            "openapi_url": "/openapi.json",
        }
    return {"docs_url": None, "redoc_url": None, "openapi_url": None}


def _is_loopback_origin(origin: str) -> bool:
    parsed = urlparse((origin or "").strip())
    host = (parsed.hostname or "").lower()
    return host in {"localhost", "127.0.0.1", "::1"}


def google_readiness_public(
    *,
    configured: bool,
    skip_verification: bool,
    client_ids_count: int,
    app_env: str,
) -> dict:
    payload = {
        "configured": configured,
        "production_safe": bool(configured) and not skip_verification,
    }
    if app_env == "development":
        payload["client_ids_count"] = client_ids_count
        payload["skip_verification"] = skip_verification
    return payload


def frontend_return_url_allowed(url: str, frontend_url: str = "") -> bool:
    """Payment/OAuth return URLs stay on localhost or our frontend host."""
    parsed = urlparse((url or "").strip())
    host = (parsed.hostname or "").lower()
    if not host or parsed.scheme not in ("http", "https"):
        return False
    if parsed.username or parsed.password:
        return False
    if host in {"localhost", "127.0.0.1", "::1"}:
        return True
    if host in {"haneat.app", "www.haneat.app"}:
        return parsed.scheme == "https"
    frontend = urlparse(frontend_url or "")
    allowed = (frontend.hostname or "").lower()
    return bool(allowed) and host == allowed


def cors_origins_for_env(origins: list[str], app_env: str) -> list[str]:
    """Always allow the production web hosts. Drop loopback CORS in production."""
    merged = list(dict.fromkeys([*(origins or []), *_PRODUCTION_WEB_ORIGINS]))
    if app_env == "development":
        return merged
    return [origin for origin in merged if not _is_loopback_origin(origin)]
