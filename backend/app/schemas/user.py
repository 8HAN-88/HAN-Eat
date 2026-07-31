"""
Pydantic схемы для пользователей
"""
from pydantic import BaseModel, Field, model_validator
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
    show_last_seen: bool = True
    show_read_receipts: bool = True
    paid_message_stars: int = 0
    created_at: datetime
    subscription_type: Optional[str] = "free"
    scan_credits: Optional[int] = None
    is_admin: bool = False
    is_moderator: bool = False
    trust_score: Optional[float] = None
    email_verified: bool = False
    legal_consent_required: bool = True
    legal_consent_version: Optional[str] = None
    legal_consent_at: Optional[datetime] = None
    phone_linked: bool = False
    phone: Optional[str] = None

    @model_validator(mode="wrap")
    @classmethod
    def _from_orm(cls, data: Any, handler, info):
        result = handler(data)
        updates = {}
        if hasattr(data, "email_verified_at"):
            verified = getattr(data, "email_verified_at", None) is not None
            linked = bool(getattr(data, "phone_hash", None))
            if result.email_verified != verified:
                updates["email_verified"] = verified
            if result.phone_linked != linked:
                updates["phone_linked"] = linked
        if hasattr(data, "email"):
            from app.services.legal_consent_service import consent_required

            required = consent_required(data)
            if result.legal_consent_required != required:
                updates["legal_consent_required"] = required
        include_phone = bool((getattr(info, "context", None) or {}).get(
            "include_phone", False
        ))
        if include_phone and hasattr(data, "phone_e164"):
            phone = getattr(data, "phone_e164", None)
            if result.phone != phone:
                updates["phone"] = phone
        elif result.phone is not None:
            updates["phone"] = None
        if updates:
            return result.model_copy(update=updates)
        return result

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


class LinkPhoneRequest(BaseModel):
    phone: str = Field(..., min_length=8, max_length=32)


class LinkPhoneResponse(BaseModel):
    ok: bool = True
    phone_linked: bool = True
    phone: Optional[str] = None


class UpdateUserRequest(BaseModel):
    name: Optional[str] = None
    bio: Optional[str] = None
    is_private: Optional[bool] = None
    show_last_seen: Optional[bool] = None
    show_read_receipts: Optional[bool] = None
    paid_message_stars: Optional[int] = Field(default=None, ge=0, le=100000)
    avatar_url: Optional[str] = None
    fcm_token: Optional[str] = None  # Firebase Cloud Messaging token
    device_platform: Optional[str] = None  # android | ios | web


UserProfileResponse.model_rebuild()

