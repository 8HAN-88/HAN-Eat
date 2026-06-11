"""Fetch Open Graph metadata for external links (SSRF-safe)."""
from __future__ import annotations

import ipaddress
import logging
import re
import socket
from html import unescape
from typing import Optional
from urllib.parse import urlparse

import httpx

logger = logging.getLogger(__name__)

_MAX_BYTES = 256_000
_TIMEOUT = 5.0
_USER_AGENT = "HAN-Eat-LinkPreview/1.0"

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
