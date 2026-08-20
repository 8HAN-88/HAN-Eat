"""Canned composer replies (Telegram Business / paid)."""

from sqlalchemy import Column, ForeignKey, Integer, String

from app.core.database import Base


class QuickReply(Base):
    __tablename__ = "quick_replies"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    title = Column(String(40), nullable=False)
    text = Column(String(400), nullable=False)
    sort_order = Column(Integer, nullable=False, default=0)
