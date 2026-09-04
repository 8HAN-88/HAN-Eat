"""
Нормализация публичных URL медиа (HTTPS для production, относительные пути).
"""
from __future__ import annotations

import copy
from typing import Any, Optional
from urllib.parse import urlparse, urlunparse

from app.core.config import settings


def _is_haneat_host(host: str) -> bool:
    h = (host or "").lower()
    return h in (
        "api.haneat.app",
        "haneat.app",
        "cdn.haneat.com",
        "cdn.haneat.app",
    ) or h.endswith(".haneat.app")


def public_base_url() -> str:
    """Базовый публичный URL API; на production всегда HTTPS."""
    base = (settings.API_PUBLIC_BASE_URL or "").strip().rstrip("/")
    if not base:
        return "https://api.haneat.app"
    try:
        parsed = urlparse(base)
        if parsed.scheme == "http" and _is_haneat_host(parsed.hostname or ""):
            parsed = parsed._replace(scheme="https")
            return urlunparse(parsed).rstrip("/")
    except Exception:
        pass
    return base


def normalize_media_url(url: Optional[str]) -> str:
    """http://api.haneat.app → https; относительные пути → полный URL."""
    if not url or not isinstance(url, str):
        return url or ""
    raw = url.strip()
    if not raw:
        return ""
    if raw.startswith("/"):
        return f"{public_base_url()}{raw}"
    if not raw.startswith(("http://", "https://", "data:", "file:")):
        return f"{public_base_url()}/{raw.lstrip('/')}"
    try:
        parsed = urlparse(raw)
        if parsed.scheme == "http" and _is_haneat_host(parsed.hostname or ""):
            parsed = parsed._replace(scheme="https")
            return urlunparse(parsed)
    except Exception:
        pass
    return raw


def normalize_post_body_media(body: Any) -> Any:
    """Нормализует video_url / media[].url в body поста (копия, без мутации ORM)."""
    if not isinstance(body, dict):
        return body
    out = copy.deepcopy(body)
    if isinstance(out.get("video_url"), str):
        out["video_url"] = normalize_media_url(out["video_url"])
    if isinstance(out.get("video_thumbnail"), str):
        out["video_thumbnail"] = normalize_media_url(out["video_thumbnail"])
    media = out.get("media")
    if isinstance(media, list):
        for item in media:
            if not isinstance(item, dict):
                continue
            if isinstance(item.get("url"), str):
                item["url"] = normalize_media_url(item["url"])
            for extra in ("mp4_480p_url", "mp4_720p_url", "mp4_1080p_url", "hls_url"):
                if isinstance(item.get(extra), str):
                    item[extra] = normalize_media_url(item[extra])
            thumb = item.get("thumbnail_url") or item.get("thumbnail")
            if isinstance(thumb, str):
                if "thumbnail_url" in item:
                    item["thumbnail_url"] = normalize_media_url(thumb)
                else:
                    item["thumbnail"] = normalize_media_url(thumb)
    return out
