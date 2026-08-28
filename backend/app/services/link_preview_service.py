"""Fetch Open Graph metadata for external links (SSRF-safe)."""
from __future__ import annotations

import html
import ipaddress
import json
import logging
import re
import socket
from html import unescape
from typing import Any, Optional
from urllib.parse import urlparse

import httpx

from app.core.media_urls import _is_haneat_host

logger = logging.getLogger(__name__)

_MAX_BYTES = 256_000
_TIMEOUT = 5.0
_USER_AGENT = "HAN-Eat-LinkPreview/1.0"

_OWN_CONTENT_RE = re.compile(
    r"^/(?:app/)?(?P<kind>reel|post)/(?P<id>\d+)/?$",
    re.IGNORECASE,
)


def parse_own_content_url(url: str) -> Optional[tuple[str, int]]:
    """HanWe reel/post URL → ('reel'|'post', id). Else None."""
    raw = (url or "").strip()
    if not raw:
        return None
    if raw.lower().startswith("haneat://"):
        raw = "https://haneat.app/" + raw[9:].lstrip("/")
    if "://" not in raw and raw.startswith("/"):
        raw = "https://haneat.app" + raw
    try:
        parsed = urlparse(raw)
    except ValueError:
        return None
    host = (parsed.hostname or "").lower()
    if host.startswith("www."):
        host = host[4:]
    if host and not _is_haneat_host(host) and host not in ("localhost", "127.0.0.1"):
        return None
    path = parsed.path or ""
    match = _OWN_CONTENT_RE.match(path)
    if match is None:
        return None
    return match.group("kind").lower(), int(match.group("id"))


def preview_from_post(post: Any, *, canonical_url: str) -> dict:
    """Build a chat/OG preview from a Post row (no HTTP scrape)."""
    from app.services.notification_preview_service import post_thumbnail_url

    user = getattr(post, "user", None)
    author = ""
    if user is not None:
        author = (
            (getattr(user, "name", None) or getattr(user, "username", None) or "")
            .strip()
        )
    caption = ((getattr(post, "description", None) or "") or "").strip()
    given_title = ((getattr(post, "title", None) or "") or "").strip()
    post_type = (getattr(post, "type", None) or "").strip().lower()
    if post_type == "reel":
        title = caption or given_title or (f"Рилс · {author}" if author else "Рилс")
        description = f"{author} в HanWe" if author else "Рилс в HanWe"
    else:
        title = given_title or caption or (author or "Публикация")
        if caption and caption != title:
            description = caption
        elif author:
            description = f"{author} в HanWe"
        else:
            description = "HanWe"
    image = post_thumbnail_url(post)
    return {
        "url": canonical_url,
        "title": title,
        "description": description,
        "image_url": image,
        "site_name": "HanWe",
    }


def try_own_content_preview(db: Any, url: str) -> Optional[dict]:
    """If URL is a public HanWe reel/post, preview it from the database."""
    parsed = parse_own_content_url(url)
    if parsed is None:
        return None
    kind, post_id = parsed
    try:
        from sqlalchemy.orm import joinedload

        from app.models.post import Post

        post = (
            db.query(Post)
            .options(joinedload(Post.user))
            .filter(Post.id == post_id, Post.deleted_at.is_(None))
            .first()
        )
    except Exception:
        logger.exception("own content preview query failed")
        return None
    if post is None:
        return None
    if (getattr(post, "visibility", None) or "public") == "private":
        return None
    path_kind = "reel" if kind == "reel" or (post.type or "") == "reel" else "post"
    canonical = f"https://haneat.app/{path_kind}/{post.id}"
    return preview_from_post(post, canonical_url=canonical)


def render_own_og_html(preview: dict, *, kind: str, post_id: int) -> str:
    """Minimal HTML with OG tags + hop into the Flutter /app/ shell."""
    title = html.escape(preview.get("title") or "HanWe")
    description = html.escape(preview.get("description") or "HanWe")
    image = html.escape(
        preview.get("image_url") or "https://haneat.app/app/icons/Icon-512.png"
    )
    url = html.escape(preview.get("url") or f"https://haneat.app/{kind}/{post_id}")
    app_path = f"/app/{kind}/{post_id}"
    app_href = html.escape(app_path)
    og_type = "video.other" if kind == "reel" else "article"
    redirect_js = json.dumps(app_path)
    return (
        "<!DOCTYPE html>\n"
        '<html lang="ru">\n'
        "<head>\n"
        '  <meta charset="utf-8">\n'
        f"  <title>{title}</title>\n"
        f'  <meta name="description" content="{description}">\n'
        '  <meta property="og:site_name" content="HanWe">\n'
        f'  <meta property="og:title" content="{title}">\n'
        f'  <meta property="og:description" content="{description}">\n'
        f'  <meta property="og:image" content="{image}">\n'
        f'  <meta property="og:url" content="{url}">\n'
        f'  <meta property="og:type" content="{og_type}">\n'
        '  <meta name="twitter:card" content="summary_large_image">\n'
        f'  <meta name="twitter:title" content="{title}">\n'
        f'  <meta name="twitter:description" content="{description}">\n'
        f'  <meta name="twitter:image" content="{image}">\n'
        f'  <meta http-equiv="refresh" content="0;url={app_href}">\n'
        f'  <link rel="canonical" href="{url}">\n'
        f"  <script>location.replace({redirect_js});</script>\n"
        "</head>\n"
        "<body>\n"
        f'  <p><a href="{app_href}">Открыть в HanWe</a></p>\n'
        "</body>\n"
        "</html>\n"
    )


_OG_TAG_RE = re.compile(
    r'<meta\s+(?:[^>]*?\s)?(?:property|name)=["\']'
    r'(og:(?:title|description|image|site_name)|twitter:(?:title|description|image))'
    r'["\']\s+(?:content=["\']([^"\']*)["\']|content=([^>\s]+))',
    re.IGNORECASE,
)
_TITLE_RE = re.compile(r"<title[^>]*>([^<]+)</title>", re.IGNORECASE)


def _is_blocked_ip(ip: ipaddress._BaseAddress) -> bool:
    return (
        ip.is_private
        or ip.is_loopback
        or ip.is_link_local
        or ip.is_multicast
        or ip.is_reserved
        or ip.is_unspecified
        or str(ip) == "169.254.169.254"
    )


def _validate_public_url(url: str) -> str:
    parsed = urlparse(url.strip())
    if parsed.scheme not in ("http", "https"):
        raise ValueError("Only http/https URLs are allowed")
    if not parsed.netloc:
        raise ValueError("Invalid URL")
    host = parsed.hostname
    if not host:
        raise ValueError("Invalid URL")
    lowered = host.lower()
    if lowered in ("localhost", "127.0.0.1", "0.0.0.0") or lowered.endswith(".local"):
        raise ValueError("Blocked host")
    try:
        addr_infos = socket.getaddrinfo(host, None)
    except socket.gaierror as exc:
        raise ValueError("Could not resolve host") from exc
    for info in addr_infos:
        ip_str = info[4][0]
        try:
            ip = ipaddress.ip_address(ip_str)
        except ValueError:
            continue
        if _is_blocked_ip(ip):
            raise ValueError("Blocked host")
    return parsed.geturl()


def _extract_meta(html: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for match in _OG_TAG_RE.finditer(html):
        key = match.group(1).lower()
        value = (match.group(2) or match.group(3) or "").strip()
        if value:
            out[key] = unescape(value)
    if "og:title" not in out:
        title_match = _TITLE_RE.search(html)
        if title_match:
            out["og:title"] = unescape(title_match.group(1).strip())
    return out


def _resolve_image_url(base_url: str, image_url: Optional[str]) -> Optional[str]:
    if not image_url:
        return None
    image_url = image_url.strip()
    if image_url.startswith(("http://", "https://")):
        try:
            return _validate_public_url(image_url)
        except ValueError:
            return None
    if image_url.startswith("//"):
        parsed = urlparse(base_url)
        candidate = f"{parsed.scheme}:{image_url}"
        try:
            return _validate_public_url(candidate)
        except ValueError:
            return None
    if image_url.startswith("/"):
        parsed = urlparse(base_url)
        candidate = f"{parsed.scheme}://{parsed.netloc}{image_url}"
        try:
            return _validate_public_url(candidate)
        except ValueError:
            return None
    return None


def fetch_link_preview(url: str) -> dict:
    """Return preview dict or raise ValueError."""
    safe_url = _validate_public_url(url)
    headers = {
        "User-Agent": _USER_AGENT,
        "Accept": "text/html,application/xhtml+xml",
    }
    with httpx.Client(
        timeout=_TIMEOUT,
        follow_redirects=True,
        max_redirects=3,
    ) as client:
        response = client.get(safe_url, headers=headers)
        response.raise_for_status()
        content_type = (response.headers.get("content-type") or "").lower()
        if "text/html" not in content_type and "application/xhtml" not in content_type:
            raise ValueError("Not an HTML page")
        raw = response.content[:_MAX_BYTES]
        html = raw.decode(response.encoding or "utf-8", errors="ignore")

    meta = _extract_meta(html)
    title = meta.get("og:title") or meta.get("twitter:title")
    description = meta.get("og:description") or meta.get("twitter:description")
    image = _resolve_image_url(
        safe_url,
        meta.get("og:image") or meta.get("twitter:image"),
    )
    site_name = meta.get("og:site_name")
    parsed = urlparse(safe_url)
    host = parsed.netloc.lower()
    if host.startswith("www."):
        host = host[4:]

    return {
        "url": safe_url,
        "title": title,
        "description": description,
        "image_url": image,
        "site_name": site_name or host,
    }
