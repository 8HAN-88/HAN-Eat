"""
Pydantic схемы для комментариев
"""
from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime


class CreateCommentRequest(BaseModel):
    text: Optional[str] = None
    rating: Optional[int] = Field(default=None, ge=1, le=5)
    parent_id: Optional[int] = None  # Для ответов на комментарии


class CommentResponse(BaseModel):
    id: int
    post_id: int
    user_id: int
    text: str
    rating: Optional[int] = None
    parent_id: Optional[int] = None
    created_at: datetime
    author_name: Optional[str] = None
    author_avatar: Optional[str] = None
    
    class Config:
        from_attributes = True


class CommentsListResponse(BaseModel):
    comments: List[CommentResponse]
    total: int

