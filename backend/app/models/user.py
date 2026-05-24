"""
Модель пользователя
"""
from sqlalchemy import Column, Integer, String, Boolean, DateTime, Text, Float
from sqlalchemy.sql import func
from app.core.database import Base


class User(Base):
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(255), unique=True, index=True, nullable=False)
    email_verified_at = Column(DateTime, nullable=True)
    password_hash = Column(String(255), nullable=False)
    name = Column(String(255), nullable=False)
    username = Column(String(100), unique=True, index=True, nullable=True)
    avatar_url = Column(Text, nullable=True)
    bio = Column(Text, nullable=True)
    is_private = Column(Boolean, default=False)
    is_verified = Column(Boolean, default=False)
    subscription_type = Column(String(20), default="free")  # free | ai | creator | pro
    subscription_status = Column(String(20), default="active", nullable=False)  # active | expired | canceled | trial
    subscription_expires_at = Column(DateTime, nullable=True)
    subscription_platform = Column(String(20), nullable=True)  # ios | android | yookassa | stripe
    subscription_auto_renew = Column(Boolean, default=False, nullable=False)
    # AI scan (мягкие лимиты): банк кредитов и момент последнего начисления «суток»
    scan_credits = Column(Integer, default=5, nullable=False)
    last_scan_credit_at = Column(DateTime, nullable=True)
    # AI meal plan: free tier — 1 план / 7 дней
    meal_plan_last_generated_at = Column(DateTime, nullable=True)
    meal_plan_cooldown_ends_at = Column(DateTime, nullable=True)
    is_admin = Column(Boolean, default=False, nullable=False)
    is_moderator = Column(Boolean, default=False, nullable=False)
    trust_score = Column(Float, default=0.5, nullable=False)
    account_warnings = Column(Integer, default=0, nullable=False)
    shadow_moderation = Column(Boolean, default=False, nullable=False)
    banned_at = Column(DateTime, nullable=True)
    fcm_token = Column(String(500), nullable=True)  # Firebase Cloud Messaging token (для Android и iOS)
    device_platform = Column(String(20), nullable=True)  # android | ios | web
    country_code = Column(String(2), nullable=True)  # ISO 3166-1 alpha-2 код страны (RU, US, etc.)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
    deleted_at = Column(DateTime, nullable=True)

