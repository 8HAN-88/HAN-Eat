"""Tenor GIF catalog proxy (search + featured)."""
from __future__ import annotations

import logging
from typing import Any, Optional

import httpx

from app.core.config import settings
from app.schemas.gif import GifItemResponse, GifSearchResponse

logger = logging.getLogger(__name__)

_TENOR_BASE = "https://tenor.googleapis.com/v2"
_TIMEOUT = 8.0
_MEDIA_FILTER = "gif,tinygif,nanogif"


def tenor_configured() -> bool:
    return bool((settings.TENOR_API_KEY or "").strip())


def _pick_format(media_formats: dict[str, Any], *names: str) -> Optional[dict[str, Any]]:
    for name in names:
        fmt = media_formats.get(name)
        if isinstance(fmt, dict) and fmt.get("url"):
            return fmt
    return None


def _item_from_tenor(raw: dict[str, Any]) -> Optional[GifItemResponse]:
    media_formats = raw.get("media_formats")
    if not isinstance(media_formats, dict):
        return None
    share = _pick_format(media_formats, "gif", "mediumgif", "tinygif")
    preview = _pick_format(media_formats, "tinygif", "nanogif", "gif")
    if share is None or preview is None:
        return None
    dims = share.get("dims") or preview.get("dims") or []
    width = int(dims[0]) if isinstance(dims, (list, tuple)) and len(dims) >= 1 else None
    height = int(dims[1]) if isinstance(dims, (list, tuple)) and len(dims) >= 2 else None
    gif_id = str(raw.get("id") or "").strip()
    if not gif_id:
        return None
    return GifItemResponse(
        id=gif_id,
        title=str(raw.get("title") or raw.get("content_description") or "").strip(),
        preview_url=str(preview["url"]),
        url=str(share["url"]),
        width=width,
        height=height,
    )


async def _tenor_get(path: str, params: dict[str, Any]) -> dict[str, Any]:
    key = (settings.TENOR_API_KEY or "").strip()
    query = {
        "key": key,
        "client_key": (settings.TENOR_CLIENT_KEY or "hanwe").strip() or "hanwe",
        "media_filter": _MEDIA_FILTER,
        "contentfilter": (settings.TENOR_CONTENT_FILTER or "medium").strip() or "medium",
        "locale": (settings.TENOR_LOCALE or "ru_RU").strip() or "ru_RU",
        **params,
    }
    url = f"{_TENOR_BASE}/{path.lstrip('/')}"
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        response = await client.get(url, params=query)
        response.raise_for_status()
        data = response.json()
        if not isinstance(data, dict):
            raise ValueError("Unexpected Tenor response")
        return data


def _parse_results(data: dict[str, Any]) -> GifSearchResponse:
    items: list[GifItemResponse] = []
    for raw in data.get("results") or []:
        if not isinstance(raw, dict):
            continue
        item = _item_from_tenor(raw)
        if item is not None:
            items.append(item)
    next_pos = data.get("next")
    if next_pos is not None:
        next_pos = str(next_pos).strip() or None
    return GifSearchResponse(configured=True, next=next_pos, items=items)


async def search_gifs(
    *,
    query: str,
    limit: int = 24,
    pos: Optional[str] = None,
) -> GifSearchResponse:
    if not tenor_configured():
        return GifSearchResponse(configured=False, items=[])
    q = (query or "").strip()
    if not q:
        return GifSearchResponse(configured=True, items=[])
    params: dict[str, Any] = {
        "q": q[:64],
        "limit": max(1, min(int(limit), 50)),
    }
    if pos:
        params["pos"] = pos[:128]
    try:
        data = await _tenor_get("search", params)
    except Exception:
        logger.exception("Tenor search failed")
        raise
    return _parse_results(data)


async def featured_gifs(
    *,
    limit: int = 24,
    pos: Optional[str] = None,
) -> GifSearchResponse:
    if not tenor_configured():
        return GifSearchResponse(configured=False, items=[])
    params: dict[str, Any] = {
        "limit": max(1, min(int(limit), 50)),
    }
    if pos:
        params["pos"] = pos[:128]
    try:
        data = await _tenor_get("featured", params)
    except Exception:
        logger.exception("Tenor featured failed")
        raise
    return _parse_results(data)
