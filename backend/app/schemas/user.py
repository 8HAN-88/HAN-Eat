"""
Pydantic схемы для пользователей
"""
from pydantic import BaseModel, model_validator
from datetime import datetime
from typing import Optional, Any


class UserResponse(BaseModel):
    id: int
    email: str
    name: str
    username: Optional[str] = None
    avatar_url: Optional[str] = None
    bio: Optional[str] = None
    is_private: bool
    created_at: datetime
    subscription_type: Optional[str] = "free"
    scan_credits: Optional[int] = None
    is_admin: bool = False
    is_moderator: bool = False
    trust_score: Optional[float] = None
    email_verified: bool = False

    @model_validator(mode="wrap")
    @classmethod
    def _email_verified_from_orm(cls, data: Any, handler):
        if hasattr(data, "email_verified_at"):
            result = handler(data)
            verified = getattr(data, "email_verified_at", None) is not None
            if result.email_verified != verified:
                return result.model_copy(update={"email_verified": verified})
            return result
        return handler(data)

    class Config:
        from_attributes = True


class UserProfileResponse(UserResponse):
    stats: "UserStats"
    is_following: Optional[bool] = None
    is_followed_by: Optional[bool] = None


class UserStats(BaseModel):
    posts_count: int = 0
    reels_count: int = 0
    saved_count: int = 0
    followers_count: int = 0
    following_count: int = 0


class UpdateUserRequest(BaseModel):
    name: Optional[str] = None
    bio: Optional[str] = None
    is_private: Optional[bool] = None
    avatar_url: Optional[str] = None
    fcm_token: Optional[str] = None  # Firebase Cloud Messaging token
    device_platform: Optional[str] = None  # android | ios | web


UserProfileResponse.model_rebuild()

