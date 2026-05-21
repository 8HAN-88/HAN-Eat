"""
API endpoints для жалоб на контент
"""
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field
from app.core.database import get_db
from app.api.dependencies import get_current_user_required
from app.models.user import User
from app.models.post import Post
from app.models.comment import Comment
from app.models.community import Channel
from app.services.analytics_service import AnalyticsService
from app.services.content_report_service import (
    ContentReportService,
    VALID_REPORT_REASONS,
)


def _log_content_report(
    db,
    *,
    content_type: str,
    content_id: int,
    reporter_id: int,
    author_id: Optional[int],
    reason: str,
    escalated: bool,
) -> None:
    AnalyticsService(db).log_event(
        event_type="content_report",
        entity_type=content_type,
        entity_id=content_id,
        user_id=reporter_id,
        author_id=author_id,
        metadata={"reason": reason, "escalated": escalated},
    )

router = APIRouter()


class ReportRequest(BaseModel):
    reason: str = Field(
        ...,
        description="spam | harassment | nsfw | violence | misinformation | scam | inappropriate | copyright | other",
    )
    comment: Optional[str] = None


@router.post("/posts/{post_id}/report")
async def report_post(
    post_id: int,
    request: ReportRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Пожаловаться на пост"""
    post = db.query(Post).filter(Post.id == post_id, Post.deleted_at.is_(None)).first()
    if not post:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Post not found")
    if post.user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot report your own post"
        )

    svc = ContentReportService(db)
    _, burst = svc.create_report(
        content_type="post",
        content_id=post_id,
        reporter_user_id=current_user.id,
        reason=request.reason,
        comment=request.comment,
    )
    _log_content_report(
        db,
        content_type="post",
        content_id=post_id,
        reporter_id=current_user.id,
        author_id=post.user_id,
        reason=request.reason,
        escalated=burst,
    )
    db.commit()
    return {
        "reported": True,
        "message": "Post reported successfully",
        "escalated": burst,
    }


@router.post("/comments/{comment_id}/report")
async def report_comment(
    comment_id: int,
    request: ReportRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Пожаловаться на комментарий"""
    comment = db.query(Comment).filter(
        Comment.id == comment_id, Comment.deleted_at.is_(None)
    ).first()
    if not comment:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Comment not found")
    if comment.user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot report your own comment",
        )

    svc = ContentReportService(db)
    _, burst = svc.create_report(
        content_type="comment",
        content_id=comment_id,
        reporter_user_id=current_user.id,
        reason=request.reason,
        comment=request.comment,
    )
    _log_content_report(
        db,
        content_type="comment",
        content_id=comment_id,
        reporter_id=current_user.id,
        author_id=comment.user_id,
        reason=request.reason,
        escalated=burst,
    )
    db.commit()
    return {
        "reported": True,
        "message": "Comment reported successfully",
        "escalated": burst,
    }


@router.post("/channels/{channel_id}/report")
async def report_channel(
    channel_id: int,
    request: ReportRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Пожаловаться на канал."""
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Channel not found")
    if channel.admin_user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot report your own channel",
        )

    svc = ContentReportService(db)
    _, burst = svc.create_report(
        content_type="channel",
        content_id=channel_id,
        reporter_user_id=current_user.id,
        reason=request.reason,
        comment=request.comment,
    )
    _log_content_report(
        db,
        content_type="channel",
        content_id=channel_id,
        reporter_id=current_user.id,
        author_id=channel.admin_user_id,
        reason=request.reason,
        escalated=burst,
    )
    db.commit()
    return {"reported": True, "escalated": burst}


@router.get("/reports/reasons")
async def list_report_reasons():
    """Список причин жалобы для UI"""
    labels = {
        "spam": "Спам",
        "harassment": "Оскорбления",
        "nsfw": "NSFW",
        "violence": "Насилие",
        "misinformation": "Ложная информация",
        "scam": "Мошенничество",
        "inappropriate": "Неподходящий контент",
        "copyright": "Авторские права",
        "other": "Другое",
    }
    return {
        "reasons": [
            {"id": r, "label": labels.get(r, r)} for r in sorted(VALID_REPORT_REASONS)
        ]
    }
