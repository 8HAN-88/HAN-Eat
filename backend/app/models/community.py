"""
Модель канала
"""
from sqlalchemy import Column, Integer, String, Text, DateTime, Boolean, ForeignKey, ARRAY
from sqlalchemy.sql import func
from app.core.database import Base


class Channel(Base):
    __tablename__ = "channels"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    slug = Column(String(100), unique=True, nullable=False, index=True)
    description = Column(Text, nullable=True)
    cover_url = Column(Text, nullable=True)
    avatar_url = Column(Text, nullable=True)
    admin_user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    is_public = Column(Boolean, default=True)
    # public | private | mixed — дефолт видимости рецептов в канале
    recipe_visibility_mode = Column(String(20), default="mixed", nullable=False)
    category = Column(String(50), nullable=True, index=True)  # Категория канала (итальянская, азиатская, веган и т.д.)
    tags = Column(ARRAY(String), nullable=True)  # Теги канала (#выпечка, #здоровое)
    rules = Column(Text, nullable=True)  # Правила канала
    members_count = Column(Integer, default=0)
    posts_count = Column(Integer, default=0)
    # Настройки публикации
    auto_publish_to_feed = Column(Boolean, default=True, nullable=False)  # Автоматически публиковать в общую ленту
    auto_publish_to_menu = Column(Boolean, default=False, nullable=False)  # Рецепты канала не в общем Menu
    # Настройки взаимодействия
    allow_comments = Column(Boolean, default=True, nullable=False)  # Разрешить комментарии
    allow_likes = Column(Boolean, default=True, nullable=False)  # Разрешить лайки
    allow_reposts = Column(Boolean, default=True, nullable=False)  # Разрешить репосты
    auto_publish_reels = Column(Boolean, default=True, nullable=False)  # Автопубликация рилсов
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

