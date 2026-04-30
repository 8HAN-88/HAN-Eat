"""
API endpoints для комментариев
"""
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import Optional
from app.core.database import get_db
from app.api.dependencies import get_current_user_required
from app.models.user import User
from app.models.post import Post
from app.models.comment import Comment
from app.schemas.comment import CreateCommentRequest, CommentResponse, CommentsListResponse

router = APIRouter()


@router.post("/posts/{post_id}/comments", response_model=CommentResponse, status_code=status.HTTP_201_CREATED)
async def create_comment(
    post_id: int,
    request: CreateCommentRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Создать комментарий к посту"""
    # Проверяем, что пост существует
    post = db.query(Post).filter(
        Post.id == post_id,
        Post.deleted_at.is_(None)
    ).first()
    
    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found"
        )
    
    # Создаем комментарий
    comment = Comment(
        post_id=post_id,
        user_id=current_user.id,
        text=request.text,
        parent_id=request.parent_id,
    )
    
    db.add(comment)
    
    # Логируем событие
    from app.services.analytics_service import AnalyticsService
    analytics_service = AnalyticsService(db)
    analytics_service.log_event(
        event_type="comment",
        entity_type="post",
        entity_id=post_id,
        user_id=current_user.id,
        author_id=post.user_id,
    )
    
    # Отправляем уведомление автору поста
    from app.services.notification_service import NotificationService
    notification_service = NotificationService(db)
    notification_service.notify_comment(
        post_author_id=post.user_id,
        commenter_id=current_user.id,
        post_id=post_id,
        comment_id=comment.id,
        commenter_name=current_user.name,
        comment_text=request.text
    )
    
    db.commit()
    db.refresh(comment)
    
    # Возвращаем с информацией об авторе
    return CommentResponse(
        id=comment.id,
        post_id=comment.post_id,
        user_id=comment.user_id,
        text=comment.text,
        parent_id=comment.parent_id,
        created_at=comment.created_at,
        author_name=current_user.name,
        author_avatar=current_user.avatar_url,
    )


@router.get("/posts/{post_id}/comments", response_model=CommentsListResponse)
async def get_comments(
    post_id: int,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db)
):
    """Получить комментарии к посту"""
    # Проверяем, что пост существует
    post = db.query(Post).filter(
        Post.id == post_id,
        Post.deleted_at.is_(None)
    ).first()
    
    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found"
        )
    
    # Получаем комментарии с eager loading авторов (оптимизация для 100k пользователей)
    from sqlalchemy.orm import joinedload
    comments = db.query(Comment).options(
        joinedload(Comment.user)
    ).filter(
        Comment.post_id == post_id,
        Comment.deleted_at.is_(None),
        Comment.parent_id.is_(None)  # Только корневые комментарии
    ).order_by(
        Comment.created_at.desc()
    ).limit(limit).offset(offset).all()
    
    # Получаем общее количество
    total = db.query(func.count(Comment.id)).filter(
        Comment.post_id == post_id,
        Comment.deleted_at.is_(None),
        Comment.parent_id.is_(None)
    ).scalar() or 0
    
    # Формируем ответ (user уже загружен через eager loading)
    comment_responses = []
    for comment in comments:
        user = comment.user  # Уже загружен через joinedload
        comment_responses.append(CommentResponse(
            id=comment.id,
            post_id=comment.post_id,
            user_id=comment.user_id,
            text=comment.text,
            parent_id=comment.parent_id,
            created_at=comment.created_at,
            author_name=user.name if user else None,
            author_avatar=user.avatar_url if user else None,
        ))
    
    return CommentsListResponse(
        comments=comment_responses,
        total=total
    )


@router.delete("/comments/{comment_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_comment(
    comment_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Удалить комментарий (только свой)"""
    comment = db.query(Comment).filter(
        Comment.id == comment_id,
        Comment.deleted_at.is_(None)
    ).first()
    
    if not comment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Comment not found"
        )
    
    if comment.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only delete your own comments"
        )
    
    from datetime import datetime
    comment.deleted_at = datetime.utcnow()
    db.commit()
    
    return None

