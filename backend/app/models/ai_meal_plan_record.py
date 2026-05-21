"""Сохранённые AI-планы питания пользователя."""
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, JSON
from sqlalchemy.sql import func

from app.core.database import Base


class AiMealPlanRecord(Base):
    __tablename__ = "ai_meal_plans"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    plan_id = Column(String(64), nullable=False, index=True)
    duration_days = Column(Integer, nullable=False, default=3)
    family_size = Column(Integer, nullable=False, default=1)
    plan_data = Column(JSON, nullable=False)
    created_at = Column(DateTime, server_default=func.now(), index=True)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
