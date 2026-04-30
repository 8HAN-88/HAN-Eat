"""
Модель уведомления
"""
from sqlalchemy import Column, Integer, String, Text, DateTime, ForeignKey, Boolean, JSON
from sqlalchemy.sql import func
from app.core.database import Base


class Notification(Base):
    __tablename__ = "notifications"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)  # Кому отправлено
    type = Column(String(50), nullable=False, index=True)  # like | comment | follow | repost | mention | system
    entity_type = Column(String(20), nullable=True, index=True)  # post | comment | user | channel
    entity_id = Column(Integer, nullable=True, index=True)  # ID сущности
    actor_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)  # Кто совершил действие
    title = Column(String(255), nullable=False)
    body = Column(Text, nullable=True)
    data = Column(JSON, nullable=True)  # Дополнительные данные для push-уведомления
    is_read = Column(Boolean, default=False, index=True)
    read_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, server_default=func.now(), index=True)

