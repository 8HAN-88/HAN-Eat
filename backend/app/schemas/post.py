"""
Pydantic схемы для публикаций
"""
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from datetime import datetime


class MediaItem(BaseModel):
    type: str  # image | video
    url: str
    upload_id: Optional[str] = None


class RecipeStep(BaseModel):
    number: int
    text: str
    step: Optional[str] = None  # Дублируем для совместимости
    image_url: Optional[str] = None
    image: Optional[str] = None  # Дублируем для совместимости с фронтендом


class CreatePostRequest(BaseModel):
    type: str  # photo | recipe | reel | text
    title: Optional[str] = None
    description: Optional[str] = None
    ingredients: Optional[List[str]] = None  # для рецептов
    steps: Optional[List[RecipeStep]] = None  # для рецептов
    media: Optional[List[MediaItem]] = None
    publish_to: Optional[List[str]] = None  # ['feed', 'community:5']
    visibility: Optional[str] = "public"  # public | followers | private
    tags: Optional[List[str]] = None
    channel_id: Optional[int] = None
    # Для обратной совместимости
    community_id: Optional[int] = None
    publish_to_reels: Optional[bool] = None
    
    # Для рецептов
    prep_time_min: Optional[int] = None
    cook_time_min: Optional[int] = None
    servings: Optional[int] = None
    calories: Optional[int] = None
    scheduled_publish_at: Optional[datetime] = None


class UpdatePostRequest(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    ingredients: Optional[List[str]] = None  # для рецептов
    steps: Optional[List[RecipeStep]] = None  # для рецептов
    media: Optional[List[MediaItem]] = None
    tags: Optional[List[str]] = None
    
    # Для рецептов
    prep_time_min: Optional[int] = None
    cook_time_min: Optional[int] = None
    servings: Optional[int] = None
    calories: Optional[int] = None


class PostAuthorResponse(BaseModel):
    id: int
    name: str
    username: Optional[str] = None
    avatar_url: Optional[str] = None
    
    class Config:
        from_attributes = True


class PostResponse(BaseModel):
    id: int
    type: str
    title: Optional[str] = None
    description: Optional[str] = None
    status: str
    created_at: datetime
    user_id: int
    channel_id: Optional[int] = None
    body: Optional[Dict[str, Any]] = None
    tags: Optional[List[str]] = None
    # Для обратной совместимости
    community_id: Optional[int] = None
    # Данные автора
    author: Optional[PostAuthorResponse] = None
    # Метаданные
    likes_count: int = 0
    comments_count: int = 0
    reposts_count: Optional[int] = None
    views_count: int = 0  # Счетчик просмотров
    is_promoted: bool = False
    is_liked: bool = False
    is_saved: bool = False
    published_at: Optional[datetime] = None
    scheduled_publish_at: Optional[datetime] = None

    class Config:
        from_attributes = True
    
    @classmethod
    def model_validate(cls, obj, **kwargs):
        """Переопределяем для добавления данных автора"""
        # Получаем базовые данные
        data = {
            'id': obj.id,
            'type': obj.type,
            'title': obj.title,
            'description': obj.description,
            'status': obj.status,
            'created_at': obj.created_at,
            'user_id': obj.user_id,
            'channel_id': obj.channel_id,
            'body': obj.body,
            'tags': obj.tags or [],
            'community_id': obj.channel_id,  # Для обратной совместимости
            'published_at': obj.published_at,
            'scheduled_publish_at': getattr(obj, 'scheduled_publish_at', None),
            'likes_count': getattr(obj, 'likes_count', 0) or 0,
            'comments_count': getattr(obj, 'comments_count', 0) or 0,
            'reposts_count': getattr(obj, 'reposts_count', None),
            'views_count': getattr(obj, 'views_count', 0) or 0,
            'is_promoted': bool(getattr(obj, 'is_promoted', False)),
            'is_liked': getattr(obj, 'is_liked', False),
            'is_saved': getattr(obj, 'is_saved', False),
        }
        
        # Добавляем данные автора, если доступны
        if hasattr(obj, 'user') and obj.user:
            data['author'] = PostAuthorResponse(
                id=obj.user.id,
                name=obj.user.name,
                username=obj.user.username,
                avatar_url=obj.user.avatar_url,
            )
        else:
            data['author'] = None
        
        return cls(**data)

