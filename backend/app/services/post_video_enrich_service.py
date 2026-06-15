"""
Обогащение body.media[] транскодированными URL из video_processing.
"""
from __future__ import annotations

import copy
import re
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple
from urllib.parse import urlparse

from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.core.media_urls import normalize_media_url
from app.models.video_processing import VideoProcessing

_UPLOAD_ID_RE = re.compile(
    r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})",
    re.IGNORECASE,
)


def _basename(path: str) -> str:
    return path.rsplit("/", 1)[-1] if path else ""


def extract_upload_id_from_video_url(url: str) -> Optional[str]:
    if not url:
        return None
    path = urlparse(url).path
    name = _basename(path)
    m = _UPLOAD_ID_RE.search(name)
    return m.group(1) if m else None


def extract_file_key_from_video_url(url: str) -> Optional[str]:
    if not url:
        return None
    path = urlparse(url).path
    idx = path.find("uploads/")
    if idx < 0:
        return None
    key = path[idx:].lstrip("/")
    for suffix in ("_1080p.mp4", "_720p.mp4", "_480p.mp4"):
        if key.endswith(suffix):
            return key[: -len(suffix)] + ".mp4"
    return key


def _collect_video_refs(body: Any) -> List[Tuple[str, Optional[str]]]:
    """(upload_id, file_key) из body поста."""
    refs: List[Tuple[str, Optional[str]]] = []
    if not isinstance(body, dict):
        return refs

    candidates: List[str] = []
    if isinstance(body.get("video_url"), str):
        candidates.append(body["video_url"])
    media = body.get("media")
    if isinstance(media, list):
        for item in media:
            if not isinstance(item, dict) or item.get("type") != "video":
                continue
            for field in ("url", "mp4_1080p_url", "mp4_720p_url", "mp4_480p_url", "hls_url"):
                val = item.get(field)
                if isinstance(val, str) and val.strip():
                    candidates.append(val.strip())

    seen: Set[str] = set()
    for raw in candidates:
        uid = extract_upload_id_from_video_url(raw)
        fk = extract_file_key_from_video_url(raw)
        key = uid or fk
        if not key or key in seen:
            continue
        seen.add(key)
        refs.append((uid or "", fk))
    return refs


def _merge_processing_into_video_item(
    item: Dict[str, Any],
    proc: VideoProcessing,
) -> Dict[str, Any]:
    out = copy.deepcopy(item)
    if proc.mp4_1080p_url and not out.get("mp4_1080p_url"):
        out["mp4_1080p_url"] = normalize_media_url(proc.mp4_1080p_url)
    if proc.mp4_480p_url and not out.get("mp4_480p_url"):
        out["mp4_480p_url"] = normalize_media_url(proc.mp4_480p_url)
    if proc.mp4_720p_url and not out.get("mp4_720p_url"):
        out["mp4_720p_url"] = normalize_media_url(proc.mp4_720p_url)
    if proc.hls_url and not out.get("hls_url"):
        out["hls_url"] = normalize_media_url(proc.hls_url)
    if proc.thumbnail_url and not out.get("thumbnail_url"):
        out["thumbnail_url"] = normalize_media_url(proc.thumbnail_url)
    return out


def enrich_post_body_video_media(
    db: Session,
    body: Any,
) -> Any:
    """Добавить mp4_480p/720p/hls в video media[] по video_processing."""
    if not isinstance(body, dict):
        return body

    refs = _collect_video_refs(body)
    if not refs:
        return body

    upload_ids = {uid for uid, _ in refs if uid}
    file_keys = {fk for _, fk in refs if fk}

    filters = []
    if upload_ids:
        filters.append(VideoProcessing.upload_id.in_(upload_ids))
    if file_keys:
        filters.append(VideoProcessing.file_key.in_(file_keys))
    if not filters:
        return body

    rows: Iterable[VideoProcessing] = (
        db.query(VideoProcessing)
        .filter(
            VideoProcessing.status == "completed",
            or_(*filters),
        )
        .all()
    )

    by_upload: Dict[str, VideoProcessing] = {}
    by_file_key: Dict[str, VideoProcessing] = {}
    for row in rows:
        if row.upload_id:
            by_upload[row.upload_id] = row
        if row.file_key:
            by_file_key[row.file_key] = row

    if not by_upload and not by_file_key:
        return body

    out = copy.deepcopy(body)
    media = out.get("media")
    if not isinstance(media, list):
        return out

    new_media: List[Any] = []
    for item in media:
        if not isinstance(item, dict) or item.get("type") != "video":
            new_media.append(item)
            continue

        proc: Optional[VideoProcessing] = None
        for field in ("url", "mp4_1080p_url", "mp4_720p_url", "mp4_480p_url"):
            val = item.get(field)
            if not isinstance(val, str):
                continue
            uid = extract_upload_id_from_video_url(val)
            fk = extract_file_key_from_video_url(val)
            if uid and uid in by_upload:
                proc = by_upload[uid]
                break
            if fk and fk in by_file_key:
                proc = by_file_key[fk]
                break

        if proc is not None:
            new_media.append(_merge_processing_into_video_item(item, proc))
        else:
            new_media.append(item)

    out["media"] = new_media
    return out


def enrich_posts_video_media_batch(
    db: Session,
    bodies: Dict[int, Any],
) -> Dict[int, Any]:
    """Пакетное обогащение body по post_id."""
    if not bodies:
        return bodies
    return {
        post_id: enrich_post_body_video_media(db, body)
        for post_id, body in bodies.items()
    }
