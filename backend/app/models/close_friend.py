"""Close friends list for story privacy (Telegram-like)."""
from sqlalchemy import Column, Integer, DateTime, UniqueConstraint, CheckConstraint
from sqlalchemy.sql import func

from app.core.database import Base


class CloseFriend(Base):
    __tablename__ = "close_friends"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, nullable=False, index=True)
    friend_user_id = Column(Integer, nullable=False, index=True)
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint("user_id", "friend_user_id", name="uq_close_friends_pair"),
        CheckConstraint("user_id != friend_user_id", name="check_no_self_close_friend"),
    )
