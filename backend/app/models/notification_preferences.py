"""
Модель настроек уведомлений пользователя
"""
from sqlalchemy import Column, Integer, Boolean, ForeignKey, DateTime
from sqlalchemy.sql import func
from app.core.database import Base


class NotificationPreferences(Base):
    __tablename__ = "notification_preferences"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True, index=True)
    
    # Типы уведомлений
    likes_enabled = Column(Boolean, default=True, nullable=False)
    comments_enabled = Column(Boolean, default=True, nullable=False)
    follows_enabled = Column(Boolean, default=True, nullable=False)
    reposts_enabled = Column(Boolean, default=True, nullable=False)
    mentions_enabled = Column(Boolean, default=True, nullable=False)
    system_enabled = Column(Boolean, default=True, nullable=False)
    
    # Push уведомления (общий переключатель)
    push_enabled = Column(Boolean, default=True, nullable=False)
    
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

