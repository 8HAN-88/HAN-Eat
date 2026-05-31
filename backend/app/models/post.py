"""
Модель публикации
"""
from sqlalchemy import Column, Integer, String, Text, DateTime, Boolean, ForeignKey, ARRAY, JSON
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from app.core.database import Base


class Post(Base):
    __tablename__ = "posts"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    channel_id = Column(Integer, ForeignKey("channels.id", ondelete="SET NULL"), nullable=True, index=True)
    type = Column(String(20), nullable=False, index=True)  # photo | recipe | reel | text
    title = Column(String(500), nullable=True)
    description = Column(Text, nullable=True)
    body = Column(JSON, nullable=True)  # для рецептов: ingredients, steps
    status = Column(String(20), default="pending", index=True)  # pending | published | rejected | deleted
    visibility = Column(String(20), default="public")  # public | followers | private
    is_global_visible = Column(Boolean, default=True, nullable=False, index=True)
    is_indexed = Column(Boolean, default=True, nullable=False, index=True)
    publish_to = Column(ARRAY(String), default=[])  # ['feed', 'community:5']
    tags = Column(ARRAY(String), default=[])
    location_name = Column(String(255), nullable=True)
    location_lat = Column(String, nullable=True)
    location_lng = Column(String, nullable=True)
    created_at = Column(DateTime, server_default=func.now(), index=True)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
    published_at = Column(DateTime, nullable=True, index=True)
    scheduled_publish_at = Column(DateTime, nullable=True, index=True)
    deleted_at = Column(DateTime, nullable=True)
    views_count = Column(Integer, default=0, nullable=False)  # Счетчик просмотров
    is_promoted = Column(Boolean, default=False, nullable=False, index=True)  # Продвижение в ленте
    hidden_from_recommendations = Column(Boolean, default=False, nullable=False)

    # Relationships для оптимизации запросов (eager loading)
    # Используем lazy="select" для избежания circular imports
    user = relationship("User", foreign_keys=[user_id], lazy="select")
    channel = relationship("Channel", foreign_keys=[channel_id], lazy="select")

