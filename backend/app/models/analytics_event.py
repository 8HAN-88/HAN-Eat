"""
Модель события аналитики
"""
from sqlalchemy import Column, Integer, String, Text, DateTime, ForeignKey, JSON
from sqlalchemy.sql import func
from app.core.database import Base


class AnalyticsEvent(Base):
    __tablename__ = "analytics_events"
    
    id = Column(Integer, primary_key=True, index=True)
    event_type = Column(String(50), nullable=False, index=True)  # view | like | comment | save | share | repost | click
    entity_type = Column(String(20), nullable=False, index=True)  # post | comment | user | channel
    entity_id = Column(Integer, nullable=False, index=True)  # ID поста, комментария, пользователя или канала
    user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)  # Кто совершил действие
    author_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)  # Автор контента (для агрегации)
    event_metadata = Column(JSON, nullable=True)  # Дополнительные данные (referrer, device, etc.)
    created_at = Column(DateTime, server_default=func.now(), index=True)

