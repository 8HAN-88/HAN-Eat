"""
Модель пользователя
"""
from sqlalchemy import Column, Integer, String, Boolean, DateTime, Text
from sqlalchemy.sql import func
from app.core.database import Base


class User(Base):
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(255), unique=True, index=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    name = Column(String(255), nullable=False)
    username = Column(String(100), unique=True, index=True, nullable=True)
    avatar_url = Column(Text, nullable=True)
    bio = Column(Text, nullable=True)
    is_private = Column(Boolean, default=False)
    is_verified = Column(Boolean, default=False)
    subscription_type = Column(String(20), default="free")  # free | plus
    subscription_expires_at = Column(DateTime, nullable=True)
    is_admin = Column(Boolean, default=False, nullable=False)
    is_moderator = Column(Boolean, default=False, nullable=False)
    fcm_token = Column(String(500), nullable=True)  # Firebase Cloud Messaging token (для Android и iOS)
    device_platform = Column(String(20), nullable=True)  # android | ios | web
    country_code = Column(String(2), nullable=True)  # ISO 3166-1 alpha-2 код страны (RU, US, etc.)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
    deleted_at = Column(DateTime, nullable=True)

