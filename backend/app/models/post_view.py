"""
Модель для отслеживания просмотров постов
"""
from sqlalchemy import Column, Integer, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.sql import func
from app.core.database import Base


class PostView(Base):
    __tablename__ = "post_views"
    
    id = Column(Integer, primary_key=True, index=True)
    post_id = Column(Integer, ForeignKey("posts.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    viewed_at = Column(DateTime, server_default=func.now(), nullable=False, index=True)
    
    # Уникальное ограничение: один пользователь может просмотреть пост только один раз
    __table_args__ = (
        UniqueConstraint('post_id', 'user_id', name='_post_user_view_uc'),
    )

