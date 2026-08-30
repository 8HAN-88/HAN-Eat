"""Emoji-реакции на постах (лента и каналы)."""
from sqlalchemy import Column, DateTime, Integer, String, UniqueConstraint
from sqlalchemy.sql import func

from app.core.database import Base


class PostReaction(Base):
    __tablename__ = "post_reactions"

    id = Column(Integer, primary_key=True, index=True)
    post_id = Column(Integer, nullable=False, index=True)
    user_id = Column(Integer, nullable=False, index=True)
    emoji = Column(String(16), nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint("post_id", "user_id", name="uq_post_reaction_user"),
    )
