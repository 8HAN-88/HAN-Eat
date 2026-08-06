"""Forum topics for Telegram-like group forums."""
from sqlalchemy import (
    Column,
    Integer,
    String,
    Boolean,
    DateTime,
    ForeignKey,
    Index,
)
from sqlalchemy.sql import func

from app.core.database import Base


class ForumTopic(Base):
    __tablename__ = "forum_topics"

    id = Column(Integer, primary_key=True, index=True)
    conversation_id = Column(
        Integer,
        ForeignKey("conversations.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    title = Column(String(128), nullable=False)
    icon_emoji = Column(String(16), nullable=True)
    created_by_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    is_general = Column(Boolean, default=False, nullable=False)
    closed_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        Index("ix_forum_topics_conv_created", "conversation_id", "created_at"),
    )
