#!/usr/bin/env python3
"""
Повторный транскод видео для добавления 1080p / обновления HLS.

  cd backend && python3 scripts/retranscode_videos_1080p.py --dry-run
  cd backend && python3 scripts/retranscode_videos_1080p.py --limit 50

Критерии: status=completed, mp4_1080p_url пустой, исходник >=1080p (если известен).
"""
from __future__ import annotations

import argparse
import sys

sys.path.insert(0, ".")

from sqlalchemy import and_, or_

from app.core.database import SessionLocal
from app.models.video_processing import VideoProcessing
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


def main() -> int:
    parser = argparse.ArgumentParser(description="Retranscode videos for 1080p")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only list candidates, do not enqueue",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Max videos to requeue (0 = all eligible)",
    )
    parser.add_argument(
        "--include-unknown-resolution",
        action="store_true",
        help="Also requeue when original dimensions were not stored",
    )
    args = parser.parse_args()

    db = SessionLocal()
    try:
        query = _eligible_query(db, args.include_unknown_resolution)
        if args.limit > 0:
            rows = query.limit(args.limit).all()
        else:
            rows = query.all()

        total = len(rows)
        print(f"Eligible for 1080p retranscode: {total}")

        if total == 0:
            return 0

        for row in rows:
            dims = f"{row.original_width or '?'}x{row.original_height or '?'}"
            print(
                f"  id={row.id} upload_id={row.upload_id} "
                f"dims={dims} file_key={row.file_key}"
            )

        if args.dry_run:
            print("Dry run — nothing enqueued.")
            return 0

        enqueued = 0
        for row in rows:
            VideoQueueService.requeue_video_processing(db, row)
            if row.status == "pending":
                enqueued += 1

        print(f"Enqueued {enqueued}/{total} videos for retranscode.")
        print("Ensure haneat-video-worker is running on the server.")
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
