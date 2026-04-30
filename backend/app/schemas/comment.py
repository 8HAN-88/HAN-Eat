"""
Pydantic схемы для комментариев
"""
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


class CreateCommentRequest(BaseModel):
    text: str
    parent_id: Optional[int] = None  # Для ответов на комментарии


class CommentResponse(BaseModel):
    id: int
    post_id: int
    user_id: int
    text: str
    parent_id: Optional[int] = None
    created_at: datetime
    author_name: Optional[str] = None
    author_avatar: Optional[str] = None
    
    class Config:
        from_attributes = True


class CommentsListResponse(BaseModel):
    comments: List[CommentResponse]
    total: int

