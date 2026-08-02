"""1:1 WebRTC call sessions (Telegram-like voice/video)."""
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Index
from sqlalchemy.sql import func

from app.core.database import Base


class CallSession(Base):
    __tablename__ = "call_sessions"
    __table_args__ = (
        Index("ix_call_sessions_caller_status", "caller_id", "status"),
        Index("ix_call_sessions_callee_status", "callee_id", "status"),
    )

    id = Column(Integer, primary_key=True, index=True)
    conversation_id = Column(
        Integer, ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False, index=True
    )
    caller_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    callee_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    # voice | video
    media = Column(String(16), nullable=False, default="voice")
    # ringing | active | ended | rejected | missed | cancelled
    status = Column(String(24), nullable=False, default="ringing", index=True)
    started_at = Column(DateTime, nullable=True)
    ended_at = Column(DateTime, nullable=True)
    ended_by_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    created_at = Column(DateTime, server_default=func.now(), nullable=False, index=True)
