"""
Модель для базовой базы популярных русских рецептов
Используется для быстрого доступа без перевода и внешних API
"""
from sqlalchemy import Column, Integer, String, Text, DateTime, JSON, Index
from sqlalchemy.sql import func
from app.core.database import Base


class BaseRecipe(Base):
    """
    Базовая база популярных русских рецептов
    Используется для быстрого доступа без перевода и внешних API
    """
    __tablename__ = "base_recipes"
    
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(500), nullable=False, index=True)
    description = Column(Text, nullable=True)
    ingredients = Column(JSON, nullable=False)  # Список ингредиентов
    steps = Column(JSON, nullable=False)  # Шаги приготовления
    image_url = Column(String, nullable=True)
    calories = Column(Integer, nullable=True)
    nutrition = Column(JSON, nullable=True)  # БЖУ: {"protein": 20, "fat": 10, "carbs": 30}
    tags = Column(JSON, nullable=True)  # Теги для поиска: ["завтрак", "быстро", "мясо"]
    search_keywords = Column(JSON, nullable=True)  # Ключевые слова для поиска
    source = Column(String(100), nullable=True)  # Откуда взяли рецепт
    popularity_score = Column(Integer, default=0)  # Популярность (для сортировки)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
    
    # Индексы для быстрого поиска
    __table_args__ = (
        Index('idx_base_recipes_title', 'title'),
        # GIN индекс для JSON полей будет создан в миграции
    )




