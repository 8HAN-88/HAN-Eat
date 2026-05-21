"""
API endpoints для репостов
"""
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import Any, Optional
from pydantic import BaseModel
from app.core.database import get_db
from app.api.dependencies import get_current_user_required, get_current_user
from app.models.user import User
from app.models.post import Post
from app.models.repost import Repost
from app.models.community import Channel
from app.models.community_member import ChannelMember

router = APIRouter()


def _meaningful_text(s: Optional[str]) -> Optional[str]:
    if s is None:
        return None
    t = (s or "").strip()
    if not t or t in (".", "…", "..."):
        return None
    return t


def _title_from_post_body(body: Any) -> Optional[str]:
    if not body or not isinstance(body, dict):
        return None
    recipe = body.get("recipe")
    if isinstance(recipe, dict):
        rt = recipe.get("title")
        if isinstance(rt, str):
            mt = _meaningful_text(rt)
            if mt:
                return mt
    for key in ("title", "name", "translated_title"):
        v = body.get(key)
        if isinstance(v, str):
            mt = _meaningful_text(v)
            if mt:
                return mt
    text = body.get("text")
    if isinstance(text, str) and text.strip():
        line = text.strip().splitlines()[0].strip()
        mt = _meaningful_text(line)
        if mt:
            return line[:120] if len(line) > 120 else line
    media = body.get("media")
    if isinstance(media, list) and len(media) > 0:
        return "Медиа"
    return None


def effective_repost_source_title(post: Post) -> str:
    """Заголовок для «Репост: …» при публикации в канал (без «.» и пустых значений)."""
    t = _meaningful_text(post.title)
    if t:
        return t
    d = _meaningful_text(post.description)
    if d:
        return d[:77] + "…" if len(d) > 80 else d
    body = post.body
    if isinstance(body, dict):
        bt = _title_from_post_body(body)
        if bt:
            return bt
    return "Пост"


class CreateRepostRequest(BaseModel):
    comment: Optional[str] = None  # Комментарий к репосту


class RepostToChannelRequest(BaseModel):
    channel_id: int
    comment: Optional[str] = None


@router.post("/posts/{post_id}/repost", status_code=status.HTTP_201_CREATED)
async def create_repost(
    post_id: int,
    request: CreateRepostRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Создать репост"""
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
    
    # Проверяем, не репостнул ли уже
    existing = db.query(Repost).filter(
        Repost.user_id == current_user.id,
        Repost.post_id == post_id
    ).first()
    
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Post already reposted"
        )
    
    # Нельзя репостнуть свой пост из профиля (но можно из канала на профиль)
    if post.user_id == current_user.id and post.channel_id is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot repost your own post"
        )
    
    # Создаем репост
    repost = Repost(
        user_id=current_user.id,
        post_id=post_id,
        comment=request.comment,
    )
    
    db.add(repost)
    
    # Логируем событие
    from app.services.analytics_service import AnalyticsService
    analytics_service = AnalyticsService(db)
    analytics_service.log_event(
        event_type="repost",
        entity_type="post",
        entity_id=post_id,
        user_id=current_user.id,
        author_id=post.user_id,
    )
    
    # Отправляем уведомление автору поста
    from app.services.notification_service import NotificationService
    notification_service = NotificationService(db)
    notification_service.notify_repost(
        post_author_id=post.user_id,
        reposter_id=current_user.id,
        post_id=post_id,
        reposter_name=current_user.name
    )
    
    db.commit()
    db.refresh(repost)

    try:
        from app.services.feed_service import FeedService
        from app.core.redis_client import get_redis

        feed_service = FeedService(db, get_redis())
        feed_service.invalidate_feed_cache(current_user.id)
    except Exception:
        pass

    return {
        "reposted": True,
        "repost_id": repost.id,
        "message": "Post reposted successfully"
    }


@router.post("/posts/{post_id}/repost-to-channel", status_code=status.HTTP_201_CREATED)
async def repost_to_channel(
    post_id: int,
    request: RepostToChannelRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """One-click репост поста в канал."""
    post = db.query(Post).filter(
        Post.id == post_id,
        Post.deleted_at.is_(None)
    ).first()
    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found"
        )

    channel = db.query(Channel).filter(Channel.id == request.channel_id).first()
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Channel not found"
        )

    is_owner = channel.admin_user_id == current_user.id
    if not is_owner:
        member = db.query(ChannelMember).filter(
            ChannelMember.channel_id == channel.id,
            ChannelMember.user_id == current_user.id
        ).first()
        is_admin_or_moderator = member and member.role in ["admin", "moderator", "owner"]
        if not is_admin_or_moderator:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only channel owner, admins and moderators can repost to channel"
            )

    source_title = effective_repost_source_title(post)
    deep_link = f"haneat://post/{post.id}"
    comment = (request.comment or "").strip()
    display_title = f"Репост: {source_title}"

    repost_post = Post(
        user_id=current_user.id,
        channel_id=channel.id,
        type="text",
        title=display_title,
        description=comment if comment else None,
        body={
            "repost_original_post_id": post.id,
            "repost_deep_link": deep_link,
            "repost_original_type": post.type,
            "repost_original_title": post.title,
            "repost_original_description": post.description,
            "repost_to_channel_comment": comment or None,
        },
        publish_to=["feed", f"channel:{channel.id}"],
        visibility="public",
        tags=post.tags or [],
        status="published",
        published_at=datetime.utcnow(),
    )
    db.add(repost_post)
    channel.posts_count = (channel.posts_count or 0) + 1
    db.commit()
    db.refresh(repost_post)

    return {
        "ok": True,
        "post_id": repost_post.id,
        "channel_id": channel.id,
        "message": "Repost published to channel",
    }


@router.delete("/posts/{post_id}/repost")
async def delete_repost(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Удалить репост"""
    repost = db.query(Repost).filter(
        Repost.user_id == current_user.id,
        Repost.post_id == post_id
    ).first()
    
    if not repost:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Repost not found"
        )
    
    db.delete(repost)
    db.commit()
    
    return {"reposted": False, "message": "Repost deleted successfully"}


@router.get("/posts/{post_id}/reposts")
async def get_reposts(
    post_id: int,
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user)
):
    """Получить список пользователей, которые репостнули пост"""
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
    
    # Получаем репосты
    reposts = db.query(Repost).filter(
        Repost.post_id == post_id
    ).order_by(Repost.created_at.desc()).limit(limit).offset(offset).all()
    
    # Получаем информацию о пользователях
    user_ids = [r.user_id for r in reposts]
    users = db.query(User).filter(User.id.in_(user_ids)).all()
    users_dict = {u.id: u for u in users}
    
    reposts_data = []
    for repost in reposts:
        user = users_dict.get(repost.user_id)
        if user:
            reposts_data.append({
                "id": repost.id,
                "user": {
                    "id": user.id,
                    "name": user.name,
                    "username": user.username,
                    "avatar_url": user.avatar_url,
                },
                "comment": repost.comment,
                "created_at": repost.created_at.isoformat() if repost.created_at else None,
            })
    
    total = db.query(func.count(Repost.id)).filter(
        Repost.post_id == post_id
    ).scalar() or 0
    
    return {
        "reposts": reposts_data,
        "total": total,
    }


@router.get("/posts/{post_id}/is_reposted")
async def is_post_reposted(
    post_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Проверить, репостнул ли пользователь пост"""
    reposted = db.query(Repost).filter(
        Repost.user_id == current_user.id,
        Repost.post_id == post_id
    ).first() is not None
    
    return {"is_reposted": reposted}

