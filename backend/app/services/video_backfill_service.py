"""
Бэкфилл транскодинга: посты с видео без video_processing / без 1080p.
"""
from __future__ import annotations

import os
import re
from dataclasses import dataclass
from typing import Iterable, List, Optional

from botocore.exceptions import ClientError
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.models.post import Post
from app.models.video_processing import VideoProcessing
from app.services.media_service import MediaService
from app.services.post_video_enrich_service import (
    extract_file_key_from_video_url,
    extract_upload_id_from_video_url,
)
from app.services.video_queue_service import VideoQueueService

_USER_ID_RE = re.compile(r"uploads/user_(\d+)/")


@dataclass
class VideoBackfillCandidate:
    post_id: int
    file_key: str
    upload_id: str
    user_id: int
    source_url: str
    local_path: Optional[str]


def _user_id_from_file_key(file_key: str) -> Optional[int]:
    m = _USER_ID_RE.search(file_key)
    return int(m.group(1)) if m else None


def _resolve_local_path(file_key: str) -> Optional[str]:
    cwd = os.getcwd()
    candidates = [
        os.path.join(cwd, file_key),
        os.path.join(cwd, "..", file_key),
        os.path.join("/root/HAN-Eat/backend", file_key),
        os.path.join("/root/HAN-Eat", file_key),
    ]
    for path in candidates:
        if os.path.isfile(path) and os.path.getsize(path) > 4096:
            return os.path.abspath(path)
    return None


def _needs_transcode_row(row: Optional[VideoProcessing]) -> bool:
    if row is None:
        return True
    if row.status in ("pending", "processing"):
        return False
    if row.status == "failed":
        return True
    return not row.mp4_1080p_url and not row.hls_url


def collect_post_video_candidates(db: Session) -> List[VideoBackfillCandidate]:
    out: List[VideoBackfillCandidate] = []
    seen_keys: set[str] = set()

    posts: Iterable[Post] = (
        db.query(Post)
        .filter(Post.type.in_(["reel", "photo", "text", "video"]))
        .order_by(Post.id.asc())
        .all()
    )

    for post in posts:
        body = post.body if isinstance(post.body, dict) else {}
        media = body.get("media")
        if not isinstance(media, list):
            video_url = body.get("video_url")
            if isinstance(video_url, str) and video_url.strip():
                media = [{"type": "video", "url": video_url.strip()}]
            else:
                continue

        for item in media:
            if not isinstance(item, dict) or item.get("type") != "video":
                continue
            url = item.get("url")
            if not isinstance(url, str) or not url.strip():
                continue

            file_key = extract_file_key_from_video_url(url)
            upload_id = extract_upload_id_from_video_url(url)
            if not file_key or not upload_id:
                continue
            if file_key in seen_keys:
                continue

            existing = (
                db.query(VideoProcessing)
                .filter(
                    or_(
                        VideoProcessing.file_key == file_key,
                        VideoProcessing.upload_id == upload_id,
                    )
                )
                .first()
            )
            if not _needs_transcode_row(existing):
                continue

            user_id = post.user_id or _user_id_from_file_key(file_key)
            if not user_id:
                continue

            seen_keys.add(file_key)
            out.append(
                VideoBackfillCandidate(
                    post_id=post.id,
                    file_key=file_key,
                    upload_id=upload_id,
                    user_id=user_id,
                    source_url=url.strip(),
                    local_path=_resolve_local_path(file_key),
                )
            )
    return out


def _s3_has_object(media: MediaService, file_key: str) -> bool:
    if not media.s3_client:
        return False
    try:
        media.s3_client.head_object(Bucket=media.bucket, Key=file_key)
        return True
    except ClientError:
        return False


def ensure_source_on_s3(
    media: MediaService,
    file_key: str,
    local_path: Optional[str],
    *,
    dry_run: bool,
) -> bool:
    if _s3_has_object(media, file_key):
        return True
    if not local_path or not media.s3_client:
        return False
    if dry_run:
        print(f"    would upload to S3: {local_path} -> {file_key}")
        return True
    media.s3_client.upload_file(local_path, media.bucket, file_key)
    return _s3_has_object(media, file_key)


def enqueue_post_video_backfill(
    db: Session,
    candidate: VideoBackfillCandidate,
    *,
    dry_run: bool,
) -> bool:
    media = MediaService()

    if not ensure_source_on_s3(
        media,
        candidate.file_key,
        candidate.local_path,
        dry_run=dry_run,
    ):
        print(
            f"  SKIP post={candidate.post_id}: no S3 object and no local file "
            f"for {candidate.file_key}"
        )
        return False

    existing = (
        db.query(VideoProcessing)
        .filter(
            or_(
                VideoProcessing.file_key == candidate.file_key,
                VideoProcessing.upload_id == candidate.upload_id,
            )
        )
        .first()
    )

    if dry_run:
        action = "requeue" if existing else "enqueue"
        print(
            f"  would {action} post={candidate.post_id} "
            f"upload_id={candidate.upload_id} file_key={candidate.file_key}"
        )
        return True

    if existing:
        if existing.status in ("pending", "processing"):
            return False
        VideoQueueService.requeue_video_processing(db, existing)
        return existing.status == "pending"

    row = VideoQueueService.enqueue_video_processing(
        db=db,
        upload_id=candidate.upload_id,
        file_key=candidate.file_key,
        user_id=candidate.user_id,
    )
    return row.status == "pending"
