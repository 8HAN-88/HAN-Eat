"""
Модель Stories / Моментов.
"""
from sqlalchemy import (
    Column,
    Integer,
    String,
    Text,
    DateTime,
    Boolean,
    ForeignKey,
    Index,
    UniqueConstraint,
)
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
    # public | followers | close_friends | private
    visibility = Column(String(20), default="public", nullable=False)
    views_count = Column(Integer, default=0, nullable=False)
    is_active = Column(Boolean, default=True, nullable=False, index=True)
    keep_in_archive = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime, server_default=func.now(), index=True)
    expires_at = Column(DateTime, nullable=False, index=True)
    deleted_at = Column(DateTime, nullable=True, index=True)

    user = relationship("User", foreign_keys=[user_id], lazy="select")
    views = relationship("StoryView", back_populates="story", cascade="all, delete-orphan")
    reactions = relationship(
        "StoryReaction", back_populates="story", cascade="all, delete-orphan"
    )

    __table_args__ = (
        Index("idx_stories_active_expires", "is_active", "expires_at"),
        Index("idx_stories_user_created", "user_id", "created_at"),
    )


class StoryView(Base):
    """Per-user story view (Telegram-like viewers list)."""

    __tablename__ = "story_views"

    id = Column(Integer, primary_key=True, index=True)
    story_id = Column(
        Integer, ForeignKey("stories.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    viewed_at = Column(DateTime, server_default=func.now(), nullable=False)

    story = relationship("Story", back_populates="views")
    user = relationship("User", foreign_keys=[user_id], lazy="select")

    __table_args__ = (
        UniqueConstraint("story_id", "user_id", name="uq_story_view_user"),
    )


class StoryReaction(Base):
    """One emoji reaction per user per story."""

    __tablename__ = "story_reactions"

    id = Column(Integer, primary_key=True, index=True)
    story_id = Column(
        Integer, ForeignKey("stories.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    emoji = Column(String(16), nullable=False)
    created_at = Column(DateTime, server_default=func.now(), nullable=False)

    story = relationship("Story", back_populates="reactions")
    user = relationship("User", foreign_keys=[user_id], lazy="select")

    __table_args__ = (
        UniqueConstraint("story_id", "user_id", name="uq_story_reaction_user"),
    )
