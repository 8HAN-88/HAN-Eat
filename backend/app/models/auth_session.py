"""Server-side auth sessions (active devices)."""
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Index
from sqlalchemy.sql import func

from app.core.database import Base


class AuthSession(Base):
    __tablename__ = "auth_sessions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    jti = Column(String(64), nullable=False, unique=True, index=True)
    device_name = Column(String(120), nullable=True)
    device_platform = Column(String(40), nullable=True)
    user_agent = Column(String(512), nullable=True)
    ip_address = Column(String(64), nullable=True)
    created_at = Column(DateTime, server_default=func.now(), nullable=False)
    last_seen_at = Column(DateTime, server_default=func.now(), nullable=False)
    revoked_at = Column(DateTime, nullable=True, index=True)

    __table_args__ = (
        Index("ix_auth_sessions_user_revoked", "user_id", "revoked_at"),
    )
