"""Telegram Premium Saved Messages tags."""

from sqlalchemy import (
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import relationship

from app.core.database import Base


class SavedTag(Base):
    __tablename__ = "saved_tags"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    title = Column(String(40), nullable=False)
    emoji = Column(String(32), nullable=True)
    sort_order = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, server_default=func.now())

    links = relationship("SavedMessageTag", back_populates="tag", cascade="all, delete-orphan")


class SavedMessageTag(Base):
    __tablename__ = "saved_message_tags"

    id = Column(Integer, primary_key=True, index=True)
    tag_id = Column(
        Integer, ForeignKey("saved_tags.id", ondelete="CASCADE"), nullable=False, index=True
    )
    message_id = Column(
        Integer, ForeignKey("messages.id", ondelete="CASCADE"), nullable=False, index=True
    )

    tag = relationship("SavedTag", back_populates="links")

    __table_args__ = (
        UniqueConstraint("tag_id", "message_id", name="uq_saved_tag_message"),
    )
