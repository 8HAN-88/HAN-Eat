"""Preview helpers for in-app notifications."""
from __future__ import annotations

from typing import Any, Dict, Optional

from app.core.media_urls import normalize_media_url
from app.models.post import Post


def post_thumbnail_url(post: Post) -> Optional[str]:
    body = post.body if isinstance(post.body, dict) else {}
    video_thumb = body.get("video_thumbnail")
    if isinstance(video_thumb, str) and video_thumb.strip():
        return normalize_media_url(video_thumb.strip())

    media = body.get("media")
    if isinstance(media, list):
        for item in media:
            if not isinstance(item, dict):
                continue
            item_type = item.get("type")
            if item_type == "image":
                url = item.get("url")
                if isinstance(url, str) and url.strip():
                    return normalize_media_url(url.strip())
            if item_type == "video":
                thumb = item.get("thumbnail_url") or item.get("thumbnail")
                if isinstance(thumb, str) and thumb.strip():
                    return normalize_media_url(thumb.strip())
                url = item.get("url")
                if isinstance(url, str) and url.strip():
                    return normalize_media_url(url.strip())

    for key in ("image", "source_image"):
        raw = body.get(key)
        if isinstance(raw, str) and raw.strip():
            return normalize_media_url(raw.strip())
    return None


def post_preview_for_notifications(post: Post) -> Dict[str, Any]:
    return {
        "post_type": post.type,
        "thumbnail_url": post_thumbnail_url(post),
    }
