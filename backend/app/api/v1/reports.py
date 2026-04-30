"""
API endpoints для жалоб на контент
"""
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from pydantic import BaseModel
from app.core.database import get_db
from app.api.dependencies import get_current_user_required
from app.models.user import User
from app.models.post import Post
from app.models.comment import Comment
from app.models.moderation_queue import ModerationQueue, ModerationReason

router = APIRouter()


class ReportRequest(BaseModel):
    reason: str  # spam | inappropriate | copyright | other
    comment: Optional[str] = None


@router.post("/posts/{post_id}/report")
async def report_post(
    post_id: int,
    request: ReportRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Пожаловаться на пост"""
    # Проверяем, существует ли пост
    post = db.query(Post).filter(
        Post.id == post_id,
        Post.deleted_at.is_(None)
    ).first()
    
    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found"
        )
    
    # Нельзя пожаловаться на свой пост
    if post.user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot report your own post"
        )
    
    # Проверяем, не жаловался ли уже
    existing = db.query(ModerationQueue).filter(
        ModerationQueue.content_type == "post",
        ModerationQueue.content_id == post_id,
        ModerationQueue.flagged_by_user_id == current_user.id,
        ModerationQueue.status == "pending"
    ).first()
    
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Already reported this post"
        )
    
    # Создаем запись в очереди модерации
    moderation_item = ModerationQueue(
        content_type="post",
        content_id=post_id,
        user_id=post.user_id,
        status="pending",
        reason="reported",
        flagged_by_user_id=current_user.id,
        moderation_comment=request.comment,
    )
    
    # Если пост был опубликован, меняем статус на pending
    if post.status == "published":
        post.status = "pending"
    
    db.add(moderation_item)
    db.commit()
    
    return {
        "reported": True,
        "message": "Post reported successfully"
    }


@router.post("/comments/{comment_id}/report")
async def report_comment(
    comment_id: int,
    request: ReportRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Пожаловаться на комментарий"""
    # Проверяем, существует ли комментарий
    comment = db.query(Comment).filter(
        Comment.id == comment_id,
        Comment.deleted_at.is_(None)
    ).first()
    
    if not comment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Comment not found"
        )
    
    # Нельзя пожаловаться на свой комментарий
    if comment.user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot report your own comment"
        )
    
    # Проверяем, не жаловался ли уже
    existing = db.query(ModerationQueue).filter(
        ModerationQueue.content_type == "comment",
        ModerationQueue.content_id == comment_id,
        ModerationQueue.flagged_by_user_id == current_user.id,
        ModerationQueue.status == "pending"
    ).first()
    
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Already reported this comment"
        )
    
    # Создаем запись в очереди модерации
    moderation_item = ModerationQueue(
        content_type="comment",
        content_id=comment_id,
        user_id=comment.user_id,
        status="pending",
        reason="reported",
        flagged_by_user_id=current_user.id,
        moderation_comment=request.comment,
    )
    
    db.add(moderation_item)
    db.commit()
    
    return {
        "reported": True,
        "message": "Comment reported successfully"
    }

