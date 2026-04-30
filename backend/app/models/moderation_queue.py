"""
Модель очереди модерации
"""
from sqlalchemy import Column, Integer, String, Text, DateTime, ForeignKey, Enum
from sqlalchemy.sql import func
from sqlalchemy.dialects.postgresql import ENUM
from app.core.database import Base
import enum


class ModerationStatus(str, enum.Enum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"


class ModerationReason(str, enum.Enum):
    AUTO_FLAGGED = "auto_flagged"
    REPORTED = "reported"
    MANUAL = "manual"


class ModerationQueue(Base):
    __tablename__ = "moderation_queue"
    
    id = Column(Integer, primary_key=True, index=True)
    content_type = Column(String(20), nullable=False, index=True)  # post | comment | user
    content_id = Column(Integer, nullable=False, index=True)  # ID поста, комментария или пользователя
    user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    status = Column(String(20), default="pending", index=True)  # pending | approved | rejected
    reason = Column(String(20), default="auto_flagged")  # auto_flagged | reported | manual
    flagged_by_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)  # Кто пожаловался
    moderation_comment = Column(Text, nullable=True)  # Комментарий модератора
    rejection_reason = Column(String(50), nullable=True)  # spam | inappropriate | copyright | other
    moderated_by_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)  # Кто модерировал
    created_at = Column(DateTime, server_default=func.now(), index=True)
    moderated_at = Column(DateTime, nullable=True)

