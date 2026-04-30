"""
API endpoints для поиска
"""
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from typing import Optional, List
from datetime import datetime
from app.core.database import get_db
from app.api.dependencies import get_current_user, get_current_user_required
from app.models.user import User
from app.services.search_service import SearchService

router = APIRouter()


@router.get("/search/posts")
async def search_posts(
    q: str = Query(..., min_length=1, description="Поисковый запрос"),
    post_type: Optional[str] = Query(None, description="Тип поста (photo, recipe, reel, text)"),
    author_id: Optional[int] = Query(None, description="ID автора"),
    channel_id: Optional[int] = Query(None, description="ID канала"),
    tags: Optional[str] = Query(None, description="Теги (через запятую)"),
    date_from: Optional[str] = Query(None, description="Начальная дата (YYYY-MM-DD)"),
    date_to: Optional[str] = Query(None, description="Конечная дата (YYYY-MM-DD)"),
    min_likes: Optional[int] = Query(None, ge=0, description="Минимальное количество лайков"),
    min_comments: Optional[int] = Query(None, ge=0, description="Минимальное количество комментариев"),
    sort_by: str = Query("relevance", description="Сортировка (relevance, date, popularity)"),
    limit: int = Query(20, ge=1, le=100, description="Количество результатов"),
    offset: int = Query(0, ge=0, description="Смещение для пагинации"),
    current_user: Optional[User] = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Полнотекстовый поиск по постам
    
    Ищет в:
    - Названии поста (title)
    - Описании (description)
    - Тегах (tags)
    - Для рецептов: ингредиентах и шагах (body.ingredients, body.steps)
    """
    try:
        search_service = SearchService(db)
        user_id = current_user.id if current_user else None
        
        # Парсим теги
        tags_list = None
        if tags:
            tags_list = [tag.strip() for tag in tags.split(',') if tag.strip()]
        
        # Парсим даты
        date_from_obj = None
        if date_from:
            try:
                date_from_obj = datetime.strptime(date_from, "%Y-%m-%d")
            except ValueError:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid date_from format. Use YYYY-MM-DD"
                )
        
        date_to_obj = None
        if date_to:
            try:
                date_to_obj = datetime.strptime(date_to, "%Y-%m-%d")
                # Добавляем время конца дня
                date_to_obj = date_to_obj.replace(hour=23, minute=59, second=59)
            except ValueError:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid date_to format. Use YYYY-MM-DD"
                )
        
        # Валидация sort_by
        if sort_by not in ["relevance", "date", "popularity"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="sort_by must be one of: relevance, date, popularity"
            )
        
        results = search_service.search_posts(
            query=q,
            user_id=user_id,
            post_type=post_type,
            author_id=author_id,
            channel_id=channel_id,
            tags=tags_list,
            date_from=date_from_obj,
            date_to=date_to_obj,
            min_likes=min_likes,
            min_comments=min_comments,
            sort_by=sort_by,
            limit=limit,
            offset=offset
        )
        
        return results
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Search error: {str(e)}"
        )


@router.get("/search/recipes")
async def search_recipes(
    q: str = Query(..., min_length=1, description="Поисковый запрос"),
    author_id: Optional[int] = Query(None, description="ID автора"),
    tags: Optional[str] = Query(None, description="Теги (через запятую)"),
    date_from: Optional[str] = Query(None, description="Начальная дата (YYYY-MM-DD)"),
    date_to: Optional[str] = Query(None, description="Конечная дата (YYYY-MM-DD)"),
    min_likes: Optional[int] = Query(None, ge=0, description="Минимальное количество лайков"),
    min_comments: Optional[int] = Query(None, ge=0, description="Минимальное количество комментариев"),
    sort_by: str = Query("relevance", description="Сортировка (relevance, date, popularity)"),
    limit: int = Query(20, ge=1, le=100, description="Количество результатов"),
    offset: int = Query(0, ge=0, description="Смещение для пагинации"),
    current_user: Optional[User] = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Поиск по рецептам
    
    Специализированный поиск по рецептам, ищет в:
    - Названии рецепта
    - Описании
    - Ингредиентах
    - Шагах приготовления
    - Тегах
    """
    try:
        search_service = SearchService(db)
        user_id = current_user.id if current_user else None
        
        # Парсим теги
        tags_list = None
        if tags:
            tags_list = [tag.strip() for tag in tags.split(',') if tag.strip()]
        
        # Парсим даты
        date_from_obj = None
        if date_from:
            try:
                date_from_obj = datetime.strptime(date_from, "%Y-%m-%d")
            except ValueError:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid date_from format. Use YYYY-MM-DD"
                )
        
        date_to_obj = None
        if date_to:
            try:
                date_to_obj = datetime.strptime(date_to, "%Y-%m-%d")
                date_to_obj = date_to_obj.replace(hour=23, minute=59, second=59)
            except ValueError:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid date_to format. Use YYYY-MM-DD"
                )
        
        # Валидация sort_by
        if sort_by not in ["relevance", "date", "popularity"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="sort_by must be one of: relevance, date, popularity"
            )
        
        results = search_service.search_recipes(
            query=q,
            user_id=user_id,
            author_id=author_id,
            tags=tags_list,
            date_from=date_from_obj,
            date_to=date_to_obj,
            min_likes=min_likes,
            min_comments=min_comments,
            sort_by=sort_by,
            limit=limit,
            offset=offset
        )
        
        return results
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Search error: {str(e)}"
        )


@router.get("/search/suggestions")
async def get_search_suggestions(
    q: str = Query(..., min_length=1, description="Поисковый запрос для автодополнения"),
    limit: int = Query(10, ge=1, le=20, description="Количество предложений"),
    db: Session = Depends(get_db)
):
    """
    Получить предложения для автодополнения поиска
    
    Возвращает похожие теги, названия постов и ингредиенты
    """
    try:
        search_service = SearchService(db)
        suggestions = search_service.get_search_suggestions(
            query=q,
            limit=limit
        )
        
        return {
            "suggestions": suggestions
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Suggestions error: {str(e)}"
        )

