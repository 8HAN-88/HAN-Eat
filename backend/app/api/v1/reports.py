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
from app.models.conversation import Message, ConversationMember
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


@router.post("/users/{user_id}/report")
async def report_user(
    user_id: int,
    request: ReportRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Пожаловаться на пользователя."""
    if user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot report yourself",
        )
    user = (
        db.query(User)
        .filter(User.id == user_id, User.deleted_at.is_(None))
        .first()
    )
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    svc = ContentReportService(db)
    _, burst = svc.create_report(
        content_type="user",
        content_id=user_id,
        reporter_user_id=current_user.id,
        reason=request.reason,
        comment=request.comment,
    )
    _log_content_report(
        db,
        content_type="user",
        content_id=user_id,
        reporter_id=current_user.id,
        author_id=user_id,
        reason=request.reason,
        escalated=burst,
    )
    db.commit()
    return {"reported": True, "escalated": burst}


@router.post("/chats/{conversation_id}/messages/{message_id}/report")
async def report_chat_message(
    conversation_id: int,
    message_id: int,
    request: ReportRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Пожаловаться на сообщение в чате."""
    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == current_user.id,
        )
        .first()
    )
    if not member:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")
    msg = (
        db.query(Message)
        .filter(
            Message.id == message_id,
            Message.conversation_id == conversation_id,
            Message.deleted_at.is_(None),
        )
        .first()
    )
    if not msg:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Message not found")
    if msg.sender_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot report your own message",
        )

    svc = ContentReportService(db)
    _, burst = svc.create_report(
        content_type="message",
        content_id=message_id,
        reporter_user_id=current_user.id,
        reason=request.reason,
        comment=request.comment,
    )
    _log_content_report(
        db,
        content_type="message",
        content_id=message_id,
        reporter_id=current_user.id,
        author_id=msg.sender_id,
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
