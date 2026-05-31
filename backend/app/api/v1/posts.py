"""
API endpoints для публикаций
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import Optional
from app.core.database import get_db
from app.api.dependencies import get_current_user_required, get_current_user
from app.models.user import User
from app.models.post import Post
from app.schemas.post import (
    CreatePostRequest,
    PollVoteRequest,
    PostResponse,
    UpdatePostRequest,
)

router = APIRouter()


def _apply_viewer_post_flags(
    db: Session,
    post_id: int,
    response: PostResponse,
    current_user: Optional[User],
) -> PostResponse:
    """Персональные is_liked / is_saved для текущего пользователя."""
    from app.models.like import Like
    from app.models.saved_post import SavedPost

    if current_user is None:
        return response.model_copy(update={"is_liked": False, "is_saved": False})
    liked = (
        db.query(Like)
        .filter(Like.user_id == current_user.id, Like.post_id == post_id)
        .first()
        is not None
    )
    saved = (
        db.query(SavedPost)
        .filter(SavedPost.user_id == current_user.id, SavedPost.post_id == post_id)
        .first()
        is not None
    )
    return response.model_copy(update={"is_liked": liked, "is_saved": saved})


@router.post("/link/preview", response_model=dict)
async def preview_link(
    payload: dict,
    _: User = Depends(get_current_user_required),
):
    """Вернуть метаданные ссылки для live-preview на клиенте."""
    from app.services.link_preview_service import fetch_link_preview

    raw_url = str(payload.get("url") or "").strip()
    if not raw_url:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="URL is required",
        )
    return {"meta": fetch_link_preview(raw_url)}


@router.post("/{post_id}/view", status_code=status.HTTP_201_CREATED)
async def mark_post_as_viewed(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Отметить пост как прочитанный (увеличить счетчик просмотров)"""
    from app.models.post_view import PostView
    from datetime import datetime
    
    # Проверяем существование поста
    post = db.query(Post).filter(Post.id == post_id, Post.deleted_at.is_(None)).first()
    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found"
        )
    
    # Проверяем, не просмотрел ли уже пользователь этот пост
    existing_view = db.query(PostView).filter(
        PostView.post_id == post_id,
        PostView.user_id == current_user.id
    ).first()
    
    if not existing_view:
        # Создаем новую запись о просмотре
        post_view = PostView(
            post_id=post_id,
            user_id=current_user.id,
            viewed_at=datetime.utcnow()
        )
        db.add(post_view)
        
        # Увеличиваем счетчик просмотров поста
        post.views_count = (post.views_count or 0) + 1
        db.commit()
    
    return {"message": "Post marked as viewed", "views_count": post.views_count or 0}


@router.post("", response_model=PostResponse, status_code=status.HTTP_201_CREATED)
async def create_post(
    request: CreatePostRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Создать пост"""
    from datetime import datetime
    from app.services.post_poll_service import build_poll_body, enrich_body_poll

    if request.type == "poll":
        if not request.poll:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Poll data is required for poll posts",
            )
        try:
            body = build_poll_body(request.poll.question, request.poll.options)
        except ValueError as e:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(e),
            )
    elif request.type == "link":
        if not request.link or not request.link.url.strip():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Link URL is required for link posts",
            )
        from app.services.link_preview_service import fetch_link_preview

        meta = fetch_link_preview(request.link.url.strip())
        body = {
            "link_url": meta.get("url") or request.link.url.strip(),
            "link_preview": (request.link.preview or "").strip()
            or meta.get("title")
            or None,
            "link_meta": meta,
        }
    else:
        body = None

    # Формируем body для рецептов
    if request.type == "recipe":
        from app.services.recipe_body_nutrition import apply_nutrition_to_recipe_body

        body = {
            "ingredients": request.ingredients or [],
            "steps": [step.model_dump() for step in (request.steps or [])],
            "prep_time_min": request.prep_time_min,
            "cook_time_min": request.cook_time_min,
            "servings": request.servings,
        }
        apply_nutrition_to_recipe_body(
            body,
            calories=request.calories,
            protein_g=request.protein_g,
            carbs_g=request.carbs_g,
            fat_g=request.fat_g,
            fiber_g=request.fiber_g,
        )
    
    # Обрабатываем медиа
    media_items = []
    if request.media:
        for item in request.media:
            media_items.append({
                "type": item.type,
                "url": item.url,
            })
    
    # Сохраняем медиа в поле body или создаем отдельное поле
    # Пока сохраняем в body для гибкости
    if media_items:
        if body is None:
            body = {}
        body["media"] = media_items
    
    publish_to = request.publish_to
    if publish_to is None:
        publish_to = ["feed", "reels"] if request.type == "reel" else ["feed"]

    post = Post(
        user_id=current_user.id,
        type=request.type,
        title=request.title,
        description=request.description,
        body=body,
        publish_to=publish_to,
        visibility=request.visibility or "public",
        tags=request.tags or [],
    )

    channel_for_visibility = None
    
    # Если указан канал
    if request.channel_id:
        from app.models.community import Channel
        from app.models.community_member import ChannelMember
        
        channel = db.query(Channel).filter(Channel.id == request.channel_id).first()
        if not channel:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Channel not found"
            )
        
        # Проверяем, является ли пользователь владельцем, админом или модератором канала
        # Владелец канала (admin_user_id) всегда может публиковать
        is_owner = channel.admin_user_id == current_user.id
        
        if is_owner:
            # Владелец канала всегда может публиковать, пропускаем проверку участников
            pass
        else:
            # Для не-владельцев проверяем роль участника
            from app.services.channel_membership_service import MEMBER_STATUS_ACTIVE

            member = db.query(ChannelMember).filter(
                ChannelMember.channel_id == request.channel_id,
                ChannelMember.user_id == current_user.id,
                ChannelMember.status == MEMBER_STATUS_ACTIVE,
            ).first()

            is_admin_or_moderator = member and member.role in [
                "admin",
                "moderator",
                "owner",
            ]
            
            if not is_admin_or_moderator:
                # Логируем для отладки
                import logging
                logger = logging.getLogger(__name__)
                logger.warning(
                    f"User {current_user.id} (username: {current_user.username}) tried to post to channel {request.channel_id}. "
                    f"Channel owner: {channel.admin_user_id}, Is owner: {is_owner}, "
                    f"Member found: {member is not None}, Member role: {member.role if member else 'None'}"
                )
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=f"Only channel owner, admins and moderators can post to channel. "
                           f"Channel owner ID: {channel.admin_user_id}, Your ID: {current_user.id}"
                )
        
        post.channel_id = request.channel_id
        channel_for_visibility = channel
        # Обновляем счетчик постов канала
        channel.posts_count = (channel.posts_count or 0) + 1

    if request.type == "recipe":
        from app.services.subscription_service import SubscriptionService
        from app.services.recipe_visibility_service import (
            resolve_recipe_visibility,
            sync_recipe_index_flags,
        )

        has_creator = SubscriptionService(db).has_creator_access(current_user.id)
        post.visibility = resolve_recipe_visibility(
            request.visibility, channel_for_visibility, has_creator
        )
        sync_recipe_index_flags(post)
    
    from app.services.anti_spam_service import AntiSpamService
    from app.services.moderation_apply import run_post_moderation
    from datetime import datetime

    ok, spam_msg = AntiSpamService(db).check_can_create_post(current_user)
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=spam_msg or "Rate limit exceeded",
        )

    db.add(post)
    db.flush()

    from app.services.moderation_apply import raise_if_post_rejected

    from app.services.post_publish_service import (
        defer_post_if_scheduled,
        require_creator_for_schedule,
    )

    require_creator_for_schedule(db, current_user, request.scheduled_publish_at)

    scores = run_post_moderation(db, post, current_user)
    raise_if_post_rejected(db, post, scores)

    defer_post_if_scheduled(post, request.scheduled_publish_at)

    db.commit()
    db.refresh(post)

    # Загружаем пользователя для включения в ответ (eager loading)
    from sqlalchemy.orm import joinedload
    post_with_user = db.query(Post).options(joinedload(Post.user)).filter(Post.id == post.id).first()
    if post_with_user:
        post = post_with_user
    
    # Инвалидируем кэш фида для подписчиков автора (если пост опубликован)
    if post.status == "published":
        try:
            from app.core.redis_client import get_redis
            from app.models.follower import Follower
            from app.services.feed_service import FeedService
            
            redis_client = get_redis()
            feed_service = FeedService(db, redis_client)
            
            # Получаем всех подписчиков автора
            followers = db.query(Follower.follower_id).filter(
                Follower.followee_id == current_user.id
            ).all()
            follower_ids = [row[0] for row in followers]
            
            # Инвалидируем кэш для всех подписчиков
            for follower_id in follower_ids:
                feed_service.invalidate_feed_cache(follower_id)
            
            # Также инвалидируем кэш для самого автора
            feed_service.invalidate_feed_cache(current_user.id)
            
        except Exception as e:
            # Не критично, если не удалось инвалидировать кэш
            import logging
            logger = logging.getLogger(__name__)
            logger.warning(f"Failed to invalidate feed cache after post creation: {e}")
    
    pr = PostResponse.model_validate(post)
    if post.type == "poll" and post.body:
        enriched_body = enrich_body_poll(db, post.id, post.body, current_user.id)
        if enriched_body:
            pr = pr.model_copy(update={"body": enriched_body})
    return _apply_viewer_post_flags(db, post.id, pr, current_user)


@router.post("/{post_id}/poll/vote", response_model=dict)
async def vote_poll(
    post_id: int,
    request: PollVoteRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Проголосовать в опросе поста (можно изменить выбор)."""
    from app.services.post_poll_service import vote_on_poll

    try:
        poll = vote_on_poll(db, post_id, current_user.id, request.option_index)
    except ValueError as e:
        msg = str(e)
        code = status.HTTP_404_NOT_FOUND if "not found" in msg.lower() else status.HTTP_400_BAD_REQUEST
        raise HTTPException(status_code=code, detail=msg)
    return {"poll": poll}


@router.post("/{post_id}/poll/close", response_model=dict)
async def close_poll(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Закрыть опрос (только автор поста)."""
    from app.models.post import Post
    from app.services.post_poll_service import enrich_body_poll

    post = (
        db.query(Post)
        .filter(Post.id == post_id, Post.deleted_at.is_(None))
        .first()
    )
    if not post or post.type != "poll":
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Poll not found",
        )
    if post.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not allowed",
        )

    body = post.body or {}
    raw = body.get("poll") or {}
    if isinstance(raw, dict):
        raw["is_closed"] = True
        body["poll"] = raw
        post.body = body
        db.commit()

        # Инвалидируем кэш ленты автора (и подписчиков автора), чтобы закрытие отобразилось сразу
        try:
            from app.core.redis_client import get_redis
            from app.models.follower import Follower
            from app.services.feed_service import FeedService

            redis_client = get_redis()
            feed_service = FeedService(db, redis_client)

            followers = (
                db.query(Follower.follower_id)
                .filter(Follower.followee_id == current_user.id)
                .all()
            )
            follower_ids = [row[0] for row in followers]
            for follower_id in follower_ids:
                feed_service.invalidate_feed_cache(follower_id)
            feed_service.invalidate_feed_cache(current_user.id)
        except Exception:
            # Кэш не критичен — закрытие всё равно сохранено в БД.
            pass

    poll = enrich_body_poll(db, post_id, post.body, current_user.id)
    return {"poll": poll.get("poll", {}) if poll else {}}


@router.get("/{post_id}/poll/voters", response_model=dict)
async def get_poll_voters(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Список проголосовавших пользователей по вариантам опроса."""
    from app.models.post_poll_vote import PostPollVote

    post = (
        db.query(Post)
        .filter(Post.id == post_id, Post.deleted_at.is_(None))
        .first()
    )
    if not post or post.type != "poll":
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Poll not found",
        )

    raw_poll = (post.body or {}).get("poll") if isinstance(post.body, dict) else None
    raw_options = raw_poll.get("options") if isinstance(raw_poll, dict) else None
    if not isinstance(raw_options, list):
        return {"options": [], "total": 0}

    rows = (
        db.query(
            PostPollVote.option_index,
            User.id,
            User.name,
            User.username,
            User.avatar_url,
        )
        .join(User, User.id == PostPollVote.user_id)
        .filter(PostPollVote.post_id == post_id)
        .order_by(PostPollVote.created_at.desc())
        .all()
    )

    voters_by_option = {}
    for option_index, user_id, name, username, avatar_url in rows:
        voters_by_option.setdefault(int(option_index), []).append(
            {
                "id": int(user_id),
                "name": name,
                "username": username,
                "avatar_url": avatar_url,
            }
        )

    options_out = []
    total = 0
    for item in raw_options:
        if not isinstance(item, dict):
            continue
        idx = item.get("index")
        if idx is None:
            continue
        index = int(idx)
        voters = voters_by_option.get(index, [])
        total += len(voters)
        options_out.append(
            {
                "index": index,
                "text": item.get("text") or "",
                "voters": voters,
            }
        )

    return {"options": options_out, "total": total}


@router.put("/{post_id}", response_model=PostResponse)
async def update_post(
    post_id: int,
    request: UpdatePostRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Обновить пост автора (в т.ч. link-пост в ленте профиля)."""
    from app.services.recipe_body_nutrition import apply_nutrition_to_recipe_body

    post = (
        db.query(Post)
        .filter(Post.id == post_id, Post.deleted_at.is_(None))
        .first()
    )
    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found",
        )
    if post.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not allowed",
        )

    if request.title is not None:
        post.title = request.title
    if request.description is not None:
        post.description = request.description
    if request.tags is not None:
        post.tags = request.tags

    if post.type == "recipe":
        body = post.body or {}
        if request.ingredients is not None:
            body["ingredients"] = request.ingredients
        if request.steps is not None:
            body["steps"] = [step.model_dump() for step in request.steps]
        if request.prep_time_min is not None:
            body["prep_time_min"] = request.prep_time_min
        if request.cook_time_min is not None:
            body["cook_time_min"] = request.cook_time_min
        if request.servings is not None:
            body["servings"] = request.servings
        apply_nutrition_to_recipe_body(
            body,
            calories=request.calories,
            protein_g=request.protein_g,
            carbs_g=request.carbs_g,
            fat_g=request.fat_g,
            fiber_g=request.fiber_g,
        )
        post.body = body

    if request.media is not None:
        body = post.body or {}
        body["media"] = [media.model_dump() for media in request.media]
        post.body = body

    if post.type == "link" and request.link is not None:
        from app.services.link_preview_service import build_link_body

        try:
            link_body = build_link_body(request.link.url, request.link.preview)
        except ValueError as e:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(e),
            )
        body = post.body or {}
        body.update(link_body)
        post.body = body

    if post.type == "poll" and request.poll is not None:
        from app.services.post_poll_service import update_poll_in_post

        try:
            update_poll_in_post(
                db, post, request.poll.question, request.poll.options
            )
        except ValueError as e:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(e),
            )

    db.commit()
    db.refresh(post)

    # Инвалидируем кэш ленты автора и его подписчиков.
    if post.status == "published":
        try:
            from app.core.redis_client import get_redis
            from app.models.follower import Follower
            from app.services.feed_service import FeedService

            redis_client = get_redis()
            redis_client.delete(f"post:{post_id}")
            feed_service = FeedService(db, redis_client)
            followers = (
                db.query(Follower.follower_id)
                .filter(Follower.followee_id == current_user.id)
                .all()
            )
            for follower_id, in followers:
                feed_service.invalidate_feed_cache(follower_id)
            feed_service.invalidate_feed_cache(current_user.id)
        except Exception:
            pass

    from app.services.post_poll_service import enrich_body_poll

    body = post.body
    if post.type == "poll" and body:
        body = enrich_body_poll(db, post_id, body, current_user.id)
    pr = PostResponse.model_validate(post)
    if body is not None and body != post.body:
        pr = pr.model_copy(update={"body": body})
    return _apply_viewer_post_flags(db, post_id, pr, current_user)


@router.delete("/{post_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_post(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Мягкое удаление поста автора в профиле (без channel_id)."""
    from datetime import datetime

    post = (
        db.query(Post)
        .filter(Post.id == post_id, Post.deleted_at.is_(None))
        .first()
    )
    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found",
        )
    if post.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not allowed",
        )
    if post.channel_id is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Use channel endpoint to delete channel posts",
        )

    post.deleted_at = datetime.utcnow()
    db.commit()

    try:
        from app.core.redis_client import get_redis
        from app.models.follower import Follower
        from app.services.feed_service import FeedService

        redis_client = get_redis()
        redis_client.delete(f"post:{post_id}")
        feed_service = FeedService(db, redis_client)
        followers = (
            db.query(Follower.follower_id)
            .filter(Follower.followee_id == current_user.id)
            .all()
        )
        for follower_id, in followers:
            feed_service.invalidate_feed_cache(follower_id)
        feed_service.invalidate_feed_cache(current_user.id)
    except Exception:
        pass


@router.get("/{post_id}", response_model=PostResponse)
async def get_post(
    post_id: int,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user)
):
    """Получить пост"""
    # Пытаемся получить из кэша (для популярных постов)
    from app.core.redis_client import get_redis
    import json
    redis_client = get_redis()
    cache_key = f"post:{post_id}"
    
    try:
        cached_post = redis_client.get(cache_key)
        if cached_post:
            post_data = json.loads(cached_post)
            # Проверяем видимость
            if post_data.get("visibility") == "private" and (not current_user or current_user.id != post_data.get("user_id")):
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Post is private"
                )
            # Логируем просмотр (асинхронно, не блокируем ответ)
            if current_user:
                from app.services.analytics_service import AnalyticsService
                analytics_service = AnalyticsService(db)
                analytics_service.log_event(
                    event_type="view",
                    entity_type="post",
                    entity_id=post_id,
                    user_id=current_user.id,
                    author_id=post_data.get("user_id"),
                )
                db.commit()
            pr = PostResponse(**post_data)
            return _apply_viewer_post_flags(db, post_id, pr, current_user)
    except HTTPException:
        raise
    except Exception:
        # Если кэш не работает, продолжаем обычным способом
        pass
    
    # Загружаем пост с eager loading (оптимизация для 100k пользователей)
    from sqlalchemy.orm import joinedload, selectinload
    post = db.query(Post).options(
        joinedload(Post.user),
        selectinload(Post.channel)
    ).filter(
        Post.id == post_id,
        Post.deleted_at.is_(None)
    ).first()
    
    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found"
        )
    
    # Проверяем видимость
    if post.visibility == "private" and (not current_user or current_user.id != post.user_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Post is private"
        )
    
    # Логируем просмотр поста
    if current_user:
        from app.services.analytics_service import AnalyticsService
        analytics_service = AnalyticsService(db)
        analytics_service.log_event(
            event_type="view",
            entity_type="post",
            entity_id=post_id,
            user_id=current_user.id,
            author_id=post.user_id,
        )
        db.commit()
    
    # Кэшируем популярные посты (с лайками > 10) на 10 минут
    try:
        if post.likes_count and post.likes_count > 10:
            post_dict = PostResponse.model_validate(post).model_dump()
            redis_client.setex(
                cache_key,
                600,  # 10 минут
                json.dumps(post_dict, default=str)
            )
    except Exception:
        # Не критично, если кэширование не сработало
        pass
    
    from app.services.post_poll_service import enrich_body_poll

    body = post.body
    if post.type == "poll" and body:
        body = enrich_body_poll(
            db, post_id, body, current_user.id if current_user else None
        )
    pr = PostResponse.model_validate(post)
    if body is not None and body != post.body:
        pr = pr.model_copy(update={"body": body})
    return _apply_viewer_post_flags(db, post_id, pr, current_user)

