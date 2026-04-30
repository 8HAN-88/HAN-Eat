"""
Схемы для настроек уведомлений
"""
from pydantic import BaseModel
from typing import Optional


class NotificationPreferencesResponse(BaseModel):
    """Ответ с настройками уведомлений"""
    likes_enabled: bool
    comments_enabled: bool
    follows_enabled: bool
    reposts_enabled: bool
    mentions_enabled: bool
    system_enabled: bool
    push_enabled: bool
    
    class Config:
        from_attributes = True


class UpdateNotificationPreferencesRequest(BaseModel):
    """Запрос на обновление настроек уведомлений"""
    likes_enabled: Optional[bool] = None
    comments_enabled: Optional[bool] = None
    follows_enabled: Optional[bool] = None
    reposts_enabled: Optional[bool] = None
    mentions_enabled: Optional[bool] = None
    system_enabled: Optional[bool] = None
    push_enabled: Optional[bool] = None

