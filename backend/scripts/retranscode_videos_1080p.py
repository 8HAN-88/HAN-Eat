#!/usr/bin/env python3
"""
Повторный транскод видео для добавления 1080p / обновления HLS.

  cd backend && python3 scripts/retranscode_videos_1080p.py --from-posts --dry-run
  cd backend && python3 scripts/retranscode_videos_1080p.py --from-posts
  cd backend && python3 scripts/retranscode_videos_1080p.py --limit 50

Режимы:
  --from-posts   — найти видео в постах без транскодов (основной бэкфилл)
  (без флага)    — переочередить completed записи video_processing без 1080p
"""
from __future__ import annotations

import argparse
import sys

sys.path.insert(0, ".")

from sqlalchemy import or_

from app.core.database import SessionLocal
from app.models.video_processing import VideoProcessing
from app.services.video_backfill_service import (
    collect_post_video_candidates,
    enqueue_post_video_backfill,
)
from app.services.video_queue_service import VideoQueueService


def _eligible_query(db, include_unknown_resolution: bool):
    q = db.query(VideoProcessing).filter(
        VideoProcessing.status == "completed",
        VideoProcessing.mp4_1080p_url.is_(None),
        VideoProcessing.file_key.isnot(None),
    )
    if include_unknown_resolution:
        q = q.filter(
            or_(
                VideoProcessing.original_height.is_(None),
                VideoProcessing.original_height >= 1080,
                VideoProcessing.original_width >= 1920,
            )
        )
    else:
        q = q.filter(
            or_(
                VideoProcessing.original_height >= 1080,
                VideoProcessing.original_width >= 1920,
            )
        )
    return q.order_by(VideoProcessing.id.asc())


def _run_from_posts(db, *, dry_run: bool, limit: int) -> int:
    candidates = collect_post_video_candidates(db)
    if limit > 0:
        candidates = candidates[:limit]

    print(f"Post videos needing transcode: {len(candidates)}")
    for c in candidates:
        local = c.local_path or "missing"
        print(
            f"  post={c.post_id} upload_id={c.upload_id} "
            f"file_key={c.file_key} local={local}"
        )

    if dry_run:
        print("Dry run — checking S3 upload + enqueue plan:")
        for c in candidates:
            enqueue_post_video_backfill(db, c, dry_run=True)
        return 0

    enqueued = 0
    for c in candidates:
        if enqueue_post_video_backfill(db, c, dry_run=False):
            enqueued += 1

    print(f"Enqueued {enqueued}/{len(candidates)} from posts.")
    return 0


def _run_from_processing_table(
    db, *, dry_run: bool, limit: int, include_unknown_resolution: bool
) -> int:
    query = _eligible_query(db, include_unknown_resolution)
    rows = query.limit(limit).all() if limit > 0 else query.all()

    print(f"Eligible video_processing rows: {len(rows)}")
    for row in rows:
        dims = f"{row.original_width or '?'}x{row.original_height or '?'}"
        print(
            f"  id={row.id} upload_id={row.upload_id} "
            f"dims={dims} file_key={row.file_key}"
        )

    if dry_run or not rows:
        if dry_run:
            print("Dry run — nothing enqueued.")
        return 0

    enqueued = 0
    for row in rows:
        VideoQueueService.requeue_video_processing(db, row)
        if row.status == "pending":
            enqueued += 1

    print(f"Enqueued {enqueued}/{len(rows)} from video_processing.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Retranscode videos for 1080p")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--from-posts", action="store_true")
    parser.add_argument("--include-unknown-resolution", action="store_true")
    args = parser.parse_args()

    db = SessionLocal()
    try:
        if args.from_posts:
            return _run_from_posts(db, dry_run=args.dry_run, limit=args.limit)

        result = _run_from_processing_table(
            db,
            dry_run=args.dry_run,
            limit=args.limit,
            include_unknown_resolution=args.include_unknown_resolution,
        )
        if not args.dry_run:
            print("Tip: use --from-posts to backfill legacy reel uploads.")
        return result
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
