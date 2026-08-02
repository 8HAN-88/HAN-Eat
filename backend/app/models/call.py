"""WebRTC call sessions — 1:1 direct and small-group mesh."""
from sqlalchemy import (
    Column,
    Integer,
    String,
    DateTime,
    ForeignKey,
    Index,
    UniqueConstraint,
)
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
    # Null for group calls (participants table is source of truth).
    callee_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True
    )
    # direct | group
    kind = Column(String(16), nullable=False, default="direct")
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


class CallParticipant(Base):
    __tablename__ = "call_participants"
    __table_args__ = (
        UniqueConstraint("call_id", "user_id", name="uq_call_participants_call_user"),
        Index("ix_call_participants_call_status", "call_id", "status"),
    )

    id = Column(Integer, primary_key=True, index=True)
    call_id = Column(
        Integer, ForeignKey("call_sessions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    # invited | ringing | joined | left | rejected | missed
    status = Column(String(24), nullable=False, default="invited")
    joined_at = Column(DateTime, nullable=True)
    left_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, server_default=func.now(), nullable=False)
