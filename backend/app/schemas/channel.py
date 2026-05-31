"""
Pydantic схемы для каналов
"""
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


class CreateChannelRequest(BaseModel):
    name: str
    slug: str  # уникальный идентификатор (например, "healthy_life")
    description: Optional[str] = None
    cover_url: Optional[str] = None
    avatar_url: Optional[str] = None
    is_public: bool = True
    recipe_visibility_mode: str = "mixed"  # public | private | mixed
    category: Optional[str] = None  # Категория канала (итальянская, азиатская, веган и т.д.)
    tags: Optional[List[str]] = None  # Теги канала (#выпечка, #здоровое)
    auto_publish_reels: bool = True


class UpdateChannelRequest(BaseModel):
    name: Optional[str] = None
    slug: Optional[str] = None
    description: Optional[str] = None
    cover_url: Optional[str] = None
    avatar_url: Optional[str] = None
    is_public: Optional[bool] = None
    category: Optional[str] = None
    tags: Optional[List[str]] = None
    rules: Optional[str] = None  # Правила канала
    recipe_visibility_mode: Optional[str] = None
    auto_publish_to_feed: Optional[bool] = None
    auto_publish_to_menu: Optional[bool] = None
    auto_publish_reels: Optional[bool] = None
    allow_comments: Optional[bool] = None
    allow_likes: Optional[bool] = None
    allow_reposts: Optional[bool] = None


class ChannelResponse(BaseModel):
    id: int
    name: str
    slug: str
    description: Optional[str] = None
    cover_url: Optional[str] = None
    avatar_url: Optional[str] = None
    admin_user_id: int
    is_public: bool
    category: Optional[str] = None
    tags: Optional[List[str]] = None
    members_count: int
    posts_count: int
    created_at: datetime
    auto_publish_reels: bool = True
    membership_status: Optional[str] = None
    pending_join_requests_count: Optional[int] = None

    class Config:
        from_attributes = True


class ChannelDetailResponse(ChannelResponse):
    admin_user: Optional[dict] = None
    is_member: bool = False
    is_admin: bool = False
    is_owner: bool = False  # Владелец канала
    is_moderator: bool = False  # Модератор канала
    membership_status: str = "none"  # none | pending | active
    can_view_posts: bool = True
    pending_join_requests_count: Optional[int] = None
    # Участник: включены ли уведомления о канале; не участник — null
    channel_notifications_enabled: Optional[bool] = None
    rules: Optional[str] = None
    recipe_visibility_mode: str = "mixed"
    auto_publish_to_feed: bool = True
    auto_publish_to_menu: bool = False
    auto_publish_reels: bool = True
    allow_comments: bool = True
    allow_likes: bool = True
    allow_reposts: bool = True


class JoinChannelResponse(BaseModel):
    joined: bool
    pending: bool = False
    members_count: int
    membership_status: str = "none"


class ChannelNotificationsPatchRequest(BaseModel):
    enabled: bool


class ChannelMemberResponse(BaseModel):
    id: int
    user_id: int
    channel_id: int
    role: str  # owner | admin | moderator | member
    status: str = "active"
    joined_at: datetime
    user: Optional[dict] = None  # Информация о пользователе
    
    class Config:
        from_attributes = True


class ChannelJoinRequestResponse(BaseModel):
    id: int
    user_id: int
    channel_id: int
    joined_at: datetime
    user: Optional[dict] = None

    class Config:
        from_attributes = True


class UpdateChannelMemberRoleRequest(BaseModel):
    role: str  # admin | moderator | member

