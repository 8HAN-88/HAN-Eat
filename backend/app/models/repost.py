"""
Модель репоста
"""
from sqlalchemy import Column, Integer, Text, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.sql import func
from app.core.database import Base


class Repost(Base):
    __tablename__ = "reposts"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    post_id = Column(Integer, ForeignKey("posts.id", ondelete="CASCADE"), nullable=False, index=True)
    comment = Column(Text, nullable=True)  # Комментарий к репосту (опционально)
    created_at = Column(DateTime, server_default=func.now(), index=True)
    
    # Уникальное ограничение: один пользователь может репостнуть пост только один раз
    __table_args__ = (
        UniqueConstraint('user_id', 'post_id', name='uq_repost_user_post'),
    )

