"""
Legacy media image proxy + soft-retired kitchen recipe API.

HanWe is a messenger: Spoonacular/search/favorites/history/analyze return 410.
`recipe-image-proxy` stays for legacy CDN images still embedded in old posts.
"""
from __future__ import annotations

import logging
import re
from typing import Optional

import requests
from fastapi import APIRouter, HTTPException, Query, Request, status
from fastapi.responses import JSONResponse, Response

from app.core.config import settings
from app.services.text_translation import (  # noqa: F401 — re-export for callers
    TRANSLATOR_AVAILABLE,
    translate_list,
    translate_steps,
    translate_text,
)

logger = logging.getLogger(__name__)

router = APIRouter()

# Kept for meal_plan / legacy imports that still reference the constant.
SPOONACULAR_API_KEY = settings.SPOONACULAR_API_KEY

_SPOONACULAR_CARD_SIZE_RE = re.compile(
    r"-\d+x\d+(?=\.(jpg|jpeg|png|webp)$)", re.IGNORECASE
)


def _spoonacular_card_image_url(url: Optional[str]) -> Optional[str]:
    if not url:
        return None
    u = url.strip()
    if not u:
        return None
    if "spoonacular.com" in u.lower():
        return _SPOONACULAR_CARD_SIZE_RE.sub("-312x231", u)
    return u


def _proxy_allowed_image_url(image_url: str) -> bool:
    u = (image_url or "").strip()
    if not u.startswith("https://"):
        return False
    prefixes = (
        "https://img.spoonacular.com",
        "https://spoonacular.com",
        "https://firebasestorage.googleapis.com",
        "https://lh3.googleusercontent.com",
        "https://lh4.googleusercontent.com",
        "https://lh5.googleusercontent.com",
        "https://lh6.googleusercontent.com",
        "https://pbs.twimg.com",
        "https://avatars.githubusercontent.com",
        "https://secure.gravatar.com",
        "https://www.gravatar.com",
        "https://cdn.discordapp.com",
        "https://storage.googleapis.com",
        "https://s3.twcstorage.ru",
        "https://cdn.haneat.com",
        "https://cdn.haneat.app",
    )
    low = u.lower()
    return any(low.startswith(p) for p in prefixes)


def _fetch_proxied_image(url: str) -> Response:
    import urllib.parse

    if url.startswith("http"):
        image_url = url
    else:
        image_url = urllib.parse.unquote(url)

    if not _proxy_allowed_image_url(image_url):
        raise HTTPException(status_code=400, detail="Invalid image URL")

    resp = requests.get(
        image_url,
        timeout=10,
        stream=True,
        headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        },
    )
    if resp.status_code != 200:
        logger.warning(
            "Image proxy error: %s for %s...",
            resp.status_code,
            image_url[:80],
        )
        raise HTTPException(status_code=resp.status_code, detail="Failed to fetch image")

    content_type = resp.headers.get("Content-Type", "image/jpeg")
    return Response(
        content=resp.content,
        media_type=content_type,
        headers={
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, OPTIONS",
            "Access-Control-Allow-Headers": "*",
            "Cache-Control": "public, max-age=86400",
        },
    )


def _kitchen_gone() -> JSONResponse:
    return JSONResponse(
        status_code=status.HTTP_410_GONE,
        content={
            "detail": "Kitchen features were removed. HanWe is a messenger.",
            "code": "kitchen_retired",
        },
    )


@router.get("/recipe-image-proxy")
async def proxy_recipe_image_v2(
    url: str = Query(..., description="URL изображения для проксирования"),
):
    """Прокси legacy CDN / внешних HTTPS-изображений (в т.ч. старые посты)."""
    try:
        return _fetch_proxied_image(url)
    except HTTPException:
        raise
    except requests.RequestException as e:
        raise HTTPException(status_code=500, detail=f"Error fetching image: {str(e)}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Unexpected error: {str(e)}")


@router.get("/recipes/image-proxy")
async def proxy_recipe_image(
    url: str = Query(..., description="URL изображения для проксирования"),
):
    """Устаревший путь; оставлен для совместимости."""
    return await proxy_recipe_image_v2(url)


# Soft-retired kitchen surfaces (explicit paths before catch-alls).
@router.api_route(
    "/recommendations",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
    include_in_schema=False,
)
@router.api_route(
    "/analyze",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
    include_in_schema=False,
)
@router.api_route(
    "/settings",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
    include_in_schema=False,
)
@router.api_route(
    "/favorites",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
    include_in_schema=False,
)
@router.api_route(
    "/favorites/{path:path}",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
    include_in_schema=False,
)
@router.api_route(
    "/history",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
    include_in_schema=False,
)
@router.api_route(
    "/recipes",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
    include_in_schema=False,
)
@router.api_route(
    "/recipes/{path:path}",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
    include_in_schema=False,
)
async def kitchen_recipes_gone(request: Request, path: str | None = None):
    # Defensive: never 410 the image proxy if routing order changes.
    if path == "image-proxy" or (request.url.path or "").endswith(
        "/recipes/image-proxy"
    ):
        url = request.query_params.get("url")
        if not url:
            raise HTTPException(status_code=422, detail="url is required")
        return await proxy_recipe_image_v2(url)
    return _kitchen_gone()
