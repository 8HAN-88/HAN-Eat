"""Подтягивание метаданных ссылки (title/description/image)."""
from __future__ import annotations

import re
from html import unescape
from typing import Any, Dict, Optional
from urllib.parse import urlparse

import httpx


_META_RE = re.compile(
    r'<meta[^>]+(?:property|name)\s*=\s*["\'](?P<key>[^"\']+)["\'][^>]*content\s*=\s*["\'](?P<val>[^"\']*)["\'][^>]*>',
    re.IGNORECASE,
)
_TITLE_RE = re.compile(r"<title[^>]*>(?P<val>.*?)</title>", re.IGNORECASE | re.DOTALL)


def _clean(text: Optional[str]) -> Optional[str]:
    if not text:
        return None
    cleaned = unescape(re.sub(r"\s+", " ", text)).strip()
    return cleaned or None


def _first_meta(content: str, keys: list[str]) -> Optional[str]:
    found: Dict[str, str] = {}
    for m in _META_RE.finditer(content):
        key = m.group("key").strip().lower()
        val = _clean(m.group("val"))
        if val:
            found[key] = val
    for k in keys:
        v = found.get(k.lower())
        if v:
            return v
    return None


def fetch_link_preview(url: str) -> Dict[str, Any]:
    target = (url or "").strip()
    if not target:
        return {}
    if not target.startswith(("http://", "https://")):
        target = f"https://{target}"

    parsed = urlparse(target)
    domain = parsed.netloc
    result: Dict[str, Any] = {
        "url": target,
        "domain": domain,
    }

    try:
        with httpx.Client(timeout=5.0, follow_redirects=True) as client:
            response = client.get(
                target,
                headers={
                    "User-Agent": "HAN-Eat-LinkPreview/1.0 (+https://haneat.app)"
                },
            )
            if response.status_code >= 400:
                return result
            content = response.text[:250000]
            final_url = str(response.url)
            final_domain = urlparse(final_url).netloc or domain
            if final_url:
                result["url"] = final_url
            if final_domain:
                result["domain"] = final_domain

            title = _first_meta(content, ["og:title", "twitter:title"])
            if not title:
                m = _TITLE_RE.search(content)
                title = _clean(m.group("val")) if m else None
            description = _first_meta(
                content,
                ["og:description", "twitter:description", "description"],
            )
            image = _first_meta(content, ["og:image", "twitter:image"])

            if title:
                result["title"] = title
            if description:
                result["description"] = description
            if image:
                result["image"] = image
    except Exception:
        return result

    return result


def build_link_body(url: str, preview: Optional[str] = None) -> Dict[str, Any]:
    """Сформировать body-поля link-поста с OG-метаданными."""
    target = (url or "").strip()
    if not target:
        raise ValueError("Link URL is required")
    meta = fetch_link_preview(target)
    preview_text = (preview or "").strip() or meta.get("title") or None
    body: Dict[str, Any] = {
        "link_url": meta.get("url") or target,
        "link_meta": meta,
    }
    if preview_text:
        body["link_preview"] = preview_text
    return body
