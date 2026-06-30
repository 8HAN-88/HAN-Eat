"""
Модель Stories / Моментов.
"""
from sqlalchemy import Column, Integer, String, Text, DateTime, Boolean, ForeignKey, Index
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from app.core.database import Base


class Story(Base):
    __tablename__ = "stories"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    media_url = Column(Text, nullable=False)
    thumbnail_url = Column(Text, nullable=True)
    media_type = Column(String(20), nullable=False)  # image | video
    caption = Column(Text, nullable=True)
    visibility = Column(String(20), default="public", nullable=False)  # public | followers | private
    views_count = Column(Integer, default=0, nullable=False)
    is_active = Column(Boolean, default=True, nullable=False, index=True)
    created_at = Column(DateTime, server_default=func.now(), index=True)
    expires_at = Column(DateTime, nullable=False, index=True)
    deleted_at = Column(DateTime, nullable=True, index=True)

    user = relationship("User", foreign_keys=[user_id], lazy="select")

    __table_args__ = (
        Index("idx_stories_active_expires", "is_active", "expires_at"),
        Index("idx_stories_user_created", "user_id", "created_at"),
    )
