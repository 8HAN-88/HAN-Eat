"""
Модель сохраненных постов
"""
from sqlalchemy import Column, Integer, DateTime, JSON
from sqlalchemy.sql import func
from app.core.database import Base


class SavedPost(Base):
    __tablename__ = "saved_posts"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, nullable=False, index=True)
    post_id = Column(Integer, nullable=True, index=True)  # Может быть NULL для рецептов Spoonacular
    spoonacular_recipe_id = Column(Integer, nullable=True, index=True)  # ID рецепта из Spoonacular
    recipe_data = Column(JSON, nullable=True)  # Данные рецепта Spoonacular для отображения
    created_at = Column(DateTime, server_default=func.now())

