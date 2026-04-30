"""
Загрузка рилса (короткого видео) через POST /api/v1/community.
Принимает base64-видео, сохраняет файл и создаёт пост типа reel.
"""
import base64
import logging
import os
import uuid
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status, Request
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user_required
from app.core.database import get_db
from app.models.user import User
from app.models.post import Post

logger = logging.getLogger(__name__)

router = APIRouter()


class CommunityUploadRequest(BaseModel):
    title: str
    author: str
    description: str = ""
    tags: list[str] = []
    video_base64: str
    thumbnail_base64: Optional[str] = None
    avatar: Optional[str] = None
    status: str = "pending"


@router.post("/community")
async def upload_community_video(
    request_body: CommunityUploadRequest,
    request: Request,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """
    Загрузить рилс: декодировать base64-видео, сохранить файл, создать пост типа reel.
    """
    try:
        video_bytes = base64.b64decode(request_body.video_base64)
    except Exception as e:
        logger.warning(f"Community upload: invalid base64 video: {e}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Некорректные данные видео (base64)",
        )

    if len(video_bytes) > 200 * 1024 * 1024:  # 200 MB
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Размер видео не более 200 МБ",
        )

    # Сохраняем видео в uploads (как mock)
    uploads_dir = os.path.join(os.getcwd(), "uploads")
    os.makedirs(uploads_dir, exist_ok=True)
    timestamp = datetime.utcnow().strftime("%Y/%m/%d")
    upload_id = str(uuid.uuid4())
    file_key = f"uploads/user_{current_user.id}/{timestamp}/{upload_id}.mp4"
    file_path = os.path.join(os.getcwd(), file_key)
    os.makedirs(os.path.dirname(file_path), exist_ok=True)
    with open(file_path, "wb") as f:
        f.write(video_bytes)

    base_url = str(request.base_url).rstrip("/")
    video_url = f"{base_url}/api/v1/uploads/file/{file_key}"

    body = {
        "media": [{"type": "video", "url": video_url}],
    }

    now = datetime.utcnow()
    post = Post(
        user_id=current_user.id,
        type="reel",
        title=request_body.title,
        description=request_body.description or "",
        body=body,
        publish_to=["feed"],
        visibility="public",
        tags=request_body.tags or [],
        status="published",
        published_at=now,
    )
    db.add(post)
    db.commit()
    db.refresh(post)

    created_at_ts = int(post.created_at.timestamp()) if post.created_at else 0

    return {
        "video": {
            "id": post.id,
            "title": post.title or "",
            "author": request_body.author,
            "description": post.description or "",
            "video_url": video_url,
            "thumbnail": None,
            "likes": 0,
            "tags": post.tags or [],
            "created_at": created_at_ts,
            "status": "published",
        }
    }
