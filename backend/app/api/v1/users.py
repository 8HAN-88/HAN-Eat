"""
API endpoints для пользователей
"""
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import Optional
from app.core.database import get_db
from app.api.dependencies import get_current_user, get_current_user_required
from app.models.user import User
from app.models.post import Post
from app.models.follower import Follower
from app.models.saved_post import SavedPost
from app.schemas.user import UserProfileResponse, UserStats, UpdateUserRequest, UserResponse
from app.schemas.post import PostResponse
from app.schemas.notification_preferences import NotificationPreferencesResponse, UpdateNotificationPreferencesRequest
from app.models.notification_preferences import NotificationPreferences

router = APIRouter()


@router.get("/me", response_model=UserResponse)
async def get_current_user_profile(current_user: User = Depends(get_current_user_required)):
    """Получить профиль текущего пользователя"""
    return UserResponse.model_validate(current_user)


@router.get("/{user_id}", response_model=UserProfileResponse)
async def get_user_profile(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user)
):
    """Получить профиль пользователя"""
    user = db.query(User).filter(User.id == user_id, User.deleted_at.is_(None)).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    # Пытаемся получить статистику из кэша
    from app.core.redis_client import get_redis
    import json
    redis_client = get_redis()
    cache_key = f"user_stats:{user_id}"
    
    try:
        cached_stats = redis_client.get(cache_key)
        if cached_stats:
            stats_dict = json.loads(cached_stats)
            stats = UserStats(**stats_dict)
        else:
            # Оптимизированные отдельные запросы (быстрее чем один сложный запрос)
            # Только личные посты (без постов из каналов)
            posts_count = db.query(func.count(Post.id)).filter(
                Post.user_id == user_id,
                Post.status == "published",
                Post.deleted_at.is_(None),
                Post.channel_id.is_(None)  # Исключаем посты из каналов
            ).scalar() or 0
            
            reels_count = db.query(func.count(Post.id)).filter(
                Post.user_id == user_id,
                Post.type == "reel",
                Post.status == "published",
                Post.deleted_at.is_(None),
                Post.channel_id.is_(None)  # Исключаем посты из каналов
            ).scalar() or 0
            
            followers_count = db.query(func.count(Follower.id)).filter(
                Follower.followee_id == user_id
            ).scalar() or 0
            
            following_count = db.query(func.count(Follower.id)).filter(
                Follower.follower_id == user_id
            ).scalar() or 0
            
            # Получаем количество сохраненных постов
            saved_count = db.query(func.count(SavedPost.id)).filter(
                SavedPost.user_id == user_id
            ).scalar() or 0
            
            stats = UserStats(
                posts_count=posts_count,
                reels_count=reels_count,
                saved_count=saved_count,
                followers_count=followers_count,
                following_count=following_count,
            )
            
            # Кэшируем статистику на 5 минут
            redis_client.setex(
                cache_key,
                300,  # 5 минут
                json.dumps(stats.model_dump())
            )
    except Exception as e:
        # Если кэш не работает, используем прямой запрос
        import logging
        logger = logging.getLogger(__name__)
        logger.warning(f"Failed to use cache for user stats: {e}")
        
        posts_count = db.query(func.count(Post.id)).filter(
            Post.user_id == user_id,
            Post.status == "published",
            Post.deleted_at.is_(None),
            Post.channel_id.is_(None)  # Исключаем посты из каналов
        ).scalar() or 0
        
        reels_count = db.query(func.count(Post.id)).filter(
            Post.user_id == user_id,
            Post.type == "reel",
            Post.status == "published",
            Post.deleted_at.is_(None),
            Post.channel_id.is_(None)  # Исключаем посты из каналов
        ).scalar() or 0
        
        followers_count = db.query(func.count(Follower.id)).filter(
            Follower.followee_id == user_id
        ).scalar() or 0
        
        following_count = db.query(func.count(Follower.id)).filter(
            Follower.follower_id == user_id
        ).scalar() or 0
        
        # Получаем количество сохраненных постов
        saved_count = db.query(func.count(SavedPost.id)).filter(
            SavedPost.user_id == user_id
        ).scalar() or 0
        
        stats = UserStats(
            posts_count=posts_count,
            reels_count=reels_count,
            saved_count=saved_count,
            followers_count=followers_count,
            following_count=following_count,
        )
    
    # Проверяем подписки (если есть текущий пользователь) - оптимизированный запрос
    is_following = None
    is_followed_by = None
    if current_user and current_user.id != user_id:
        # Один запрос для обеих проверок
        follow_checks = db.query(
            func.count(case((Follower.follower_id == current_user.id, Follower.id))).label('is_following'),
            func.count(case((Follower.follower_id == user_id, Follower.id))).label('is_followed_by')
        ).filter(
            (Follower.follower_id == current_user.id) & (Follower.followee_id == user_id) |
            (Follower.follower_id == user_id) & (Follower.followee_id == current_user.id)
        ).first()
        
        # Проще: два отдельных быстрых запроса
        is_following = db.query(Follower).filter(
            Follower.follower_id == current_user.id,
            Follower.followee_id == user_id
        ).first() is not None
        
        is_followed_by = db.query(Follower).filter(
            Follower.follower_id == user_id,
            Follower.followee_id == current_user.id
        ).first() is not None
    
    return UserProfileResponse(
        **UserResponse.model_validate(user).model_dump(),
        stats=stats,
        is_following=is_following,
        is_followed_by=is_followed_by
    )


@router.patch("/me", response_model=UserResponse)
async def update_user_profile(
    request: UpdateUserRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Обновить профиль текущего пользователя"""
    if request.name is not None:
        current_user.name = request.name
    if request.bio is not None:
        current_user.bio = request.bio
    if request.is_private is not None:
        current_user.is_private = request.is_private
    if request.avatar_url is not None:
        current_user.avatar_url = request.avatar_url
    if request.fcm_token is not None:
        current_user.fcm_token = request.fcm_token
    
    if request.device_platform is not None:
        # Валидация платформы
        if request.device_platform not in ["android", "ios", "web"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="device_platform must be one of: android, ios, web"
            )
        current_user.device_platform = request.device_platform
    
    db.commit()
    db.refresh(current_user)
    
    return UserResponse.model_validate(current_user)


@router.get("/{user_id}/posts")
async def get_user_posts(
    user_id: int,
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    post_type: Optional[str] = Query(None, regex="^(photo|recipe|reel|text|post)$"),
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user)
):
    """Получить посты пользователя"""
    user = db.query(User).filter(User.id == user_id, User.deleted_at.is_(None)).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    # Проверяем приватность
    if user.is_private and (not current_user or current_user.id != user_id):
        # Проверяем подписку
        from app.models.follower import Follower
        is_following = db.query(Follower).filter(
            Follower.follower_id == (current_user.id if current_user else 0),
            Follower.followee_id == user_id
        ).first() is not None
        
        if not is_following:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="User profile is private"
            )
    
    # Получаем посты (только личные посты, без постов из каналов)
    query = db.query(Post).filter(
        Post.user_id == user_id,
        Post.status == "published",
        Post.deleted_at.is_(None),
        Post.channel_id.is_(None)  # Исключаем посты из каналов
    )
    
    if post_type:
        # Если post_type == "post", фильтруем все типы кроме "reel"
        if post_type == "post":
            query = query.filter(Post.type != "reel")
        else:
            query = query.filter(Post.type == post_type)
    
    # Загружаем посты с eager loading для оптимизации
    from sqlalchemy.orm import joinedload
    posts = query.options(joinedload(Post.user)).order_by(Post.published_at.desc()).limit(limit).offset(offset).all()
    
    # Получаем количество лайков и комментариев для каждого поста
    from app.models.like import Like
    from app.models.comment import Comment
    
    posts_data = []
    for post in posts:
        likes_count = db.query(func.count(Like.id)).filter(Like.post_id == post.id).scalar() or 0
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
        
        posts_data.append({
            **PostResponse.model_validate(post).model_dump(),
            "likes_count": likes_count,
            "comments_count": comments_count,
            "is_liked": is_liked,
        })
    
    return {
        "posts": posts_data,
        "total": db.query(func.count(Post.id)).filter(
            Post.user_id == user_id,
            Post.status == "published",
            Post.deleted_at.is_(None),
            Post.channel_id.is_(None)  # Исключаем посты из каналов
        ).scalar() or 0
    }


@router.get("/me/notification-preferences", response_model=NotificationPreferencesResponse)
async def get_notification_preferences(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Получить настройки уведомлений текущего пользователя"""
    prefs = db.query(NotificationPreferences).filter(
        NotificationPreferences.user_id == current_user.id
    ).first()
    
    # Если настроек нет, создаем с дефолтными значениями
    if not prefs:
        prefs = NotificationPreferences(
            user_id=current_user.id,
            likes_enabled=True,
            comments_enabled=True,
            follows_enabled=True,
            reposts_enabled=True,
            mentions_enabled=True,
            system_enabled=True,
            push_enabled=True
        )
        db.add(prefs)
        db.commit()
        db.refresh(prefs)
    
    return NotificationPreferencesResponse.model_validate(prefs)


@router.patch("/me/notification-preferences", response_model=NotificationPreferencesResponse)
async def update_notification_preferences(
    request: UpdateNotificationPreferencesRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Обновить настройки уведомлений текущего пользователя"""
    prefs = db.query(NotificationPreferences).filter(
        NotificationPreferences.user_id == current_user.id
    ).first()
    
    # Если настроек нет, создаем
    if not prefs:
        prefs = NotificationPreferences(user_id=current_user.id)
        db.add(prefs)
    
    # Обновляем только переданные поля
    if request.likes_enabled is not None:
        prefs.likes_enabled = request.likes_enabled
    if request.comments_enabled is not None:
        prefs.comments_enabled = request.comments_enabled
    if request.follows_enabled is not None:
        prefs.follows_enabled = request.follows_enabled
    if request.reposts_enabled is not None:
        prefs.reposts_enabled = request.reposts_enabled
    if request.mentions_enabled is not None:
        prefs.mentions_enabled = request.mentions_enabled
    if request.system_enabled is not None:
        prefs.system_enabled = request.system_enabled
    if request.push_enabled is not None:
        prefs.push_enabled = request.push_enabled
    
    db.commit()
    db.refresh(prefs)
    
    return NotificationPreferencesResponse.model_validate(prefs)

