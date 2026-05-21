"""Аудит действий модераторов и админов."""
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, JSON
from sqlalchemy.sql import func
from app.core.database import Base


class ModerationAuditLog(Base):
    __tablename__ = "moderation_audit_log"

    id = Column(Integer, primary_key=True, index=True)
    moderator_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    action = Column(String(50), nullable=False, index=True)
    content_type = Column(String(20), nullable=True)
    content_id = Column(Integer, nullable=True)
    target_user_id = Column(Integer, nullable=True, index=True)
    details = Column(JSON, nullable=True)
    created_at = Column(DateTime, server_default=func.now(), index=True)
