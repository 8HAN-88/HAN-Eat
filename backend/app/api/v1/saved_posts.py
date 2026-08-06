"""
API endpoints для сохраненных постов
"""
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status, Query, Body
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import Optional, Dict, Any
from app.core.database import get_db
from app.api.dependencies import get_current_user_required, get_current_user
from app.models.user import User
from app.models.post import Post
from app.models.saved_post import SavedPost
from app.models.like import Like
from app.models.comment import Comment
from app.models.community import Channel
from app.schemas.post import PostResponse

router = APIRouter()


@router.post("/posts/{post_id}/save", status_code=status.HTTP_201_CREATED)
async def save_post(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Сохранить пост"""
    # Проверяем, существует ли пост
    post = db.query(Post).filter(
        Post.id == post_id,
        Post.deleted_at.is_(None)
    ).first()
    
    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found"
        )
    
    # Проверяем, не сохранен ли уже
    existing = db.query(SavedPost).filter(
        SavedPost.user_id == current_user.id,
        SavedPost.post_id == post_id
    ).first()
    
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Post already saved"
        )
    
    # Создаем запись о сохранении
    saved_post = SavedPost(
        user_id=current_user.id,
        post_id=post_id,
    )
    
    db.add(saved_post)
    
    # Логируем событие
    from app.services.analytics_service import AnalyticsService
    analytics_service = AnalyticsService(db)
    analytics_service.log_event(
        event_type="save",
        entity_type="post",
        entity_id=post_id,
        user_id=current_user.id,
        author_id=post.user_id,
    )
    
    db.commit()
    try:
        from app.core.redis_client import get_redis
        from app.services.feed_service import FeedService

        FeedService(db, get_redis()).invalidate_feed_cache(current_user.id)
    except Exception:
        pass
    
    return {"saved": True, "message": "Post saved successfully"}


@router.delete("/posts/{post_id}/save")
async def unsave_post(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Удалить пост из сохраненных"""
    saved_post = db.query(SavedPost).filter(
        SavedPost.user_id == current_user.id,
        SavedPost.post_id == post_id
    ).first()
    
    if not saved_post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not saved"
        )
    
    db.delete(saved_post)
    db.commit()
    try:
        from app.core.redis_client import get_redis
        from app.services.feed_service import FeedService

        FeedService(db, get_redis()).invalidate_feed_cache(current_user.id)
    except Exception:
        pass
    
    return {"saved": False, "message": "Post unsaved successfully"}


@router.get("/posts/{post_id}/is_saved")
async def is_post_saved(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Проверить, сохранен ли пост"""
    saved = db.query(SavedPost).filter(
        SavedPost.user_id == current_user.id,
        SavedPost.post_id == post_id
    ).first() is not None
    
    return {"is_saved": saved}


def _kitchen_recipe_save_gone() -> None:
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail={
            "detail": "Kitchen features were removed. HanWe is a messenger.",
            "code": "kitchen_retired",
        },
    )


@router.post("/recipes/{recipe_id}/save", status_code=status.HTTP_410_GONE)
async def save_spoonacular_recipe_retired(recipe_id: int):
    """Spoonacular recipe save retired with kitchen product."""
    _kitchen_recipe_save_gone()


@router.delete("/recipes/{recipe_id}/save", status_code=status.HTTP_410_GONE)
async def unsave_spoonacular_recipe_retired(recipe_id: int):
    """Spoonacular recipe unsave retired with kitchen product."""
    _kitchen_recipe_save_gone()


@router.get("/recipes/{recipe_id}/is_saved", status_code=status.HTTP_410_GONE)
async def is_recipe_saved_retired(recipe_id: int):
    """Spoonacular recipe saved-check retired with kitchen product."""
    _kitchen_recipe_save_gone()


@router.get("/users/{user_id}/saved")
async def get_saved_posts(
    user_id: int,
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    post_type: Optional[str] = Query(None, regex="^(photo|recipe|reel|text|post)$", description="Filter by post type"),
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user)
):
    """Получить список сохраненных постов пользователя (только владелец)."""
    if current_user is None or current_user.id != user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot access saved posts",
        )
    
    # Получаем сохраненные посты (включая рецепты Spoonacular)
    saved_posts = db.query(SavedPost).filter(
        SavedPost.user_id == user_id
    ).order_by(SavedPost.created_at.desc()).limit(limit).offset(offset).all()
    
    # Разделяем на обычные посты и рецепты Spoonacular
    post_ids = [sp.post_id for sp in saved_posts if sp.post_id is not None]
    spoonacular_recipes = [sp for sp in saved_posts if sp.spoonacular_recipe_id is not None]
    
    # Получаем посты
    posts = []
    if post_ids:
        query = db.query(Post).filter(
            Post.id.in_(post_ids),
            Post.deleted_at.is_(None)
        )
        
        # Фильтруем по типу поста, если указан
        if post_type:
            # Если post_type == "post", фильтруем все типы кроме "reel"
            if post_type == "post":
                query = query.filter(Post.type != "reel")
            else:
                query = query.filter(Post.type == post_type)
        
        posts = query.all()
    
    # Создаем словарь для быстрого доступа
    posts_dict = {p.id: p for p in posts}
    
    # Обогащаем метаданными
    enriched_posts = []
    for saved_post in saved_posts:
        # Проверяем, есть ли новые поля (для обратной совместимости)
        has_spoonacular_fields = hasattr(saved_post, 'spoonacular_recipe_id') and hasattr(saved_post, 'recipe_data')
        
        # Обрабатываем обычные посты
        if saved_post.post_id is not None:
            post = posts_dict.get(saved_post.post_id)
            if not post:
                continue
            
            # Количество лайков
            likes_count = db.query(func.count(Like.id)).filter(
                Like.post_id == post.id
            ).scalar() or 0
            
            # Количество комментариев
            comments_count = db.query(func.count(Comment.id)).filter(
                Comment.post_id == post.id,
                Comment.deleted_at.is_(None)
            ).scalar() or 0
            
            # Проверяем, лайкнул ли текущий пользователь
            is_liked = False
            if current_user:
                is_liked = db.query(Like).filter(
                    Like.user_id == current_user.id,
                    Like.post_id == post.id
                ).first() is not None
            
            # Информация об авторе
            author = db.query(User).filter(User.id == post.user_id).first()
            
            # Информация о канале (если пост из канала)
            channel_data = None
            if post.channel_id:
                channel = db.query(Channel).filter(Channel.id == post.channel_id).first()
                if channel:
                    channel_data = {
                        "id": channel.id,
                        "name": channel.name,
                        "slug": channel.slug,
                        "description": channel.description,
                        "avatar_url": channel.avatar_url,
                        "cover_url": channel.cover_url,
                    }
            
            enriched_posts.append({
                **PostResponse.model_validate(post).model_dump(),
                "likes_count": likes_count,
                "comments_count": comments_count,
                "is_liked": is_liked,
                "is_saved": True,
                "saved_at": saved_post.created_at.isoformat() if saved_post.created_at else None,
                "author": {
                    "id": author.id if author else None,
                    "name": author.name if author else None,
                    "username": author.username if author else None,
                    "avatar_url": author.avatar_url if author else None,
                } if author else None,
                "channel": channel_data,  # Добавляем информацию о канале
            })
        
        # Обрабатываем рецепты Spoonacular
        elif has_spoonacular_fields and saved_post.spoonacular_recipe_id is not None and saved_post.recipe_data:
            # Spoonacular-элементы участвуют только в "Общее" и "Рецепты".
            # В "Рилсы" (post_type == "reel") и других типах их быть не должно.
            if post_type not in (None, "recipe"):
                continue
            recipe_data = saved_post.recipe_data
            # Создаем объект поста из данных рецепта Spoonacular
            saved_at = saved_post.created_at if saved_post.created_at else None
            
            # Используем переведенные данные, если они есть, иначе оригинальные
            title = recipe_data.get("translated_title") or recipe_data.get("title") or "Рецепт"
            ingredients = recipe_data.get("translated_ingredients") or recipe_data.get("ingredients") or []
            steps = recipe_data.get("translated_steps") or recipe_data.get("steps") or []
            
            # Получаем изображение (приоритет: image > source_image)
            image_url = recipe_data.get("image") or recipe_data.get("source_image") or ""
            
            enriched_posts.append({
                "id": f"spoonacular_{saved_post.spoonacular_recipe_id}",
                "type": "recipe",
                "title": title,
                "description": recipe_data.get("summary") or "",
                "status": "published",
                "created_at": saved_at.isoformat() if saved_at else datetime.now().isoformat(),
                "published_at": saved_at.isoformat() if saved_at else None,
                "user_id": user_id,  # ID пользователя, который сохранил
                "community_id": None,
                "channel_id": None,
                "body": {
                    "ingredients": ingredients,
                    "steps": steps,
                    "calories": recipe_data.get("calories"),
                    "nutrition": recipe_data.get("nutrition"),
                    "translated_title": recipe_data.get("translated_title"),
                    "translated_ingredients": recipe_data.get("translated_ingredients"),
                    "translated_steps": recipe_data.get("translated_steps"),
                    "image": image_url,
                    "source_image": recipe_data.get("source_image") or image_url,
                    "spoonacular_recipe_id": saved_post.spoonacular_recipe_id,  # Добавляем ID для клика
                },
                "tags": None,
                "media": [
                    {
                        "type": "image",
                        "url": image_url
                    }
                ] if image_url else [],
                "likes_count": recipe_data.get("likes_count") or 0,
                "comments_count": 0,
                "reposts_count": 0,
                "views_count": 0,
                "is_liked": False,
                "is_saved": True,
                "is_reposted": False,
                "saved_at": saved_at.isoformat() if saved_at else None,
                "author": None,
                "channel": None,
                "source": "spoonacular",
                "spoonacular_recipe_id": saved_post.spoonacular_recipe_id,
            })
    
    # Сортируем по дате сохранения (новые сначала)
    enriched_posts.sort(
        key=lambda x: x.get("saved_at") or "",
        reverse=True
    )
    
    # Подсчитываем общее количество сохраненных постов с учетом фильтрации по типу
    if post_type:
        # Получаем все сохраненные посты пользователя
        all_saved_posts = db.query(SavedPost).filter(
            SavedPost.user_id == user_id
        ).all()
        all_post_ids = [sp.post_id for sp in all_saved_posts if sp.post_id is not None]
        
        # Фильтруем по типу
        total = 0
        if all_post_ids:
            total_query = db.query(func.count(Post.id)).filter(
                Post.id.in_(all_post_ids),
                Post.deleted_at.is_(None)
            )
            if post_type == "post":
                total_query = total_query.filter(Post.type != "reel")
            else:
                total_query = total_query.filter(Post.type == post_type)
            
            total = total_query.scalar() or 0
        
        # Если фильтр по типу "recipe", добавляем рецепты Spoonacular
        if post_type == "recipe":
            spoonacular_count = db.query(func.count(SavedPost.id)).filter(
                SavedPost.user_id == user_id,
                SavedPost.spoonacular_recipe_id.isnot(None)
            ).scalar() or 0
            total += spoonacular_count
    else:
        total = db.query(func.count(SavedPost.id)).filter(
            SavedPost.user_id == user_id
        ).scalar() or 0
    
    return {
        "posts": enriched_posts,
        "total": total,
    }

