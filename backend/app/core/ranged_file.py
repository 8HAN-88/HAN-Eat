"""
HTTP byte-range ответ для видео и аудио (AVPlayer / video_player на iOS требуют 206).
"""
from __future__ import annotations

import os
import re
from typing import Any, Optional, Tuple

from fastapi import Request
from fastapi.responses import FileResponse, Response

_RANGE_RE = re.compile(r"^bytes=(\d*)-(\d*)$")


def _parse_range(range_header: str, file_size: int) -> Optional[Tuple[int, int]]:
    m = _RANGE_RE.match(range_header.strip())
    if not m:
        return None
    start_s, end_s = m.group(1), m.group(2)
    if start_s == "" and end_s == "":
        return None
    if start_s == "":
        # suffix: bytes=-500
        suffix = int(end_s)
        if suffix <= 0:
            return None
        start = max(file_size - suffix, 0)
        end = file_size - 1
    elif end_s == "":
        start = int(start_s)
        end = file_size - 1
    else:
        start = int(start_s)
        end = int(end_s)
    if start < 0 or end < start or start >= file_size:
        return None
    end = min(end, file_size - 1)
    return start, end


def ranged_file_response(
    path: str,
    request: Request,
    *,
    media_type: str = "application/octet-stream",
    extra_headers: Optional[dict[str, str]] = None,
) -> Response:
    stat = os.stat(path)
    file_size = stat.st_size
    headers = {
        "Accept-Ranges": "bytes",
        "Cache-Control": "public, max-age=31536000",
    }
    if extra_headers:
        headers.update(extra_headers)

    range_header = request.headers.get("range") or request.headers.get("Range")
    if range_header and file_size > 0:
        parsed = _parse_range(range_header, file_size)
        if parsed is None:
            return Response(
                status_code=416,
                headers={
                    "Content-Range": f"bytes */{file_size}",
                    "Accept-Ranges": "bytes",
                },
            )
        start, end = parsed
        length = end - start + 1
        with open(path, "rb") as f:
            f.seek(start)
            chunk = f.read(length)
        headers.update(
            {
                "Content-Range": f"bytes {start}-{end}/{file_size}",
                "Content-Length": str(len(chunk)),
            }
        )
        return Response(content=chunk, status_code=206, media_type=media_type, headers=headers)

    return FileResponse(
        path,
        media_type=media_type,
        headers=headers,
        stat_result=stat,
        method=request.method,
    )


def content_type_for_upload_path(path: str) -> str:
    lower = path.lower()
    if lower.endswith((".jpg", ".jpeg")):
        return "image/jpeg"
    if lower.endswith(".png"):
        return "image/png"
    if lower.endswith(".gif"):
        return "image/gif"
    if lower.endswith(".webp"):
        return "image/webp"
    if lower.endswith(".mp4"):
        return "video/mp4"
    if lower.endswith(".mov"):
        return "video/quicktime"
    if lower.endswith(".m4a"):
        return "audio/mp4"
    if lower.endswith(".aac"):
        return "audio/aac"
    if lower.endswith(".mp3"):
        return "audio/mpeg"
    if lower.endswith(".webm"):
        return "audio/webm"
    if lower.endswith(".ogg"):
        return "audio/ogg"
    return "application/octet-stream"


def ranged_s3_object_response(
    s3_client: Any,
    bucket: str,
    key: str,
    request: Request,
    *,
    media_type: Optional[str] = None,
    extra_headers: Optional[dict[str, str]] = None,
) -> Response:
    """Стриминг объекта S3 с поддержкой Range (голосовые / видео с телефона)."""
    head = s3_client.head_object(Bucket=bucket, Key=key)
    file_size = int(head["ContentLength"])
    effective_type = media_type or head.get("ContentType") or content_type_for_upload_path(key)

    headers = {
        "Accept-Ranges": "bytes",
        "Cache-Control": "public, max-age=31536000",
    }
    if extra_headers:
        headers.update(extra_headers)

    range_header = request.headers.get("range") or request.headers.get("Range")
    if range_header and file_size > 0:
        parsed = _parse_range(range_header, file_size)
        if parsed is None:
            return Response(
                status_code=416,
                headers={
                    "Content-Range": f"bytes */{file_size}",
                    "Accept-Ranges": "bytes",
                },
            )
        start, end = parsed
        obj = s3_client.get_object(
            Bucket=bucket,
            Key=key,
            Range=f"bytes={start}-{end}",
        )
        chunk = obj["Body"].read()
        headers.update(
            {
                "Content-Range": f"bytes {start}-{end}/{file_size}",
                "Content-Length": str(len(chunk)),
            }
        )
        return Response(content=chunk, status_code=206, media_type=effective_type, headers=headers)

    obj = s3_client.get_object(Bucket=bucket, Key=key)
    body = obj["Body"].read()
    headers["Content-Length"] = str(len(body))
    return Response(content=body, status_code=200, media_type=effective_type, headers=headers)
