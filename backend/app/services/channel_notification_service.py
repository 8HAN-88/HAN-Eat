"""
Сервис для отправки уведомлений о событиях в каналах
"""
from sqlalchemy.orm import Session
from datetime import datetime
from typing import Optional
from app.models.notification import Notification
from app.models.community_member import ChannelMember
from app.models.community import Channel
from app.models.post import Post
from app.services.push_service import get_push_service


def send_channel_post_notification(
    db: Session,
    channel_id: int,
    post_id: int,
    post_type: str,
    post_title: Optional[str] = None,
    author_id: int = None
):
    """
    Отправить уведомления подписчикам канала о новом посте
    
    Типы уведомлений:
    - channel_post: новый пост в канале
    - channel_recipe: новый рецепт в канале
    - channel_video: новое видео в канале
    - channel_announcement: объявление от автора
    """
    # Получаем канал
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        return
    
    # Получаем всех подписчиков канала (кроме автора поста)
    subscribers = db.query(ChannelMember).filter(
        ChannelMember.channel_id == channel_id,
        ChannelMember.user_id != author_id  # Не отправляем автору
    ).all()
    
    if not subscribers:
        return
    
    # Определяем тип уведомления и текст
    notification_type = "channel_post"
    title = f"Новый пост в канале {channel.name}"
    body = post_title or "Новый пост"
    
    if post_type == "recipe":
        notification_type = "channel_recipe"
        title = f"Новый рецепт в канале {channel.name}"
        body = post_title or "Новый рецепт"
    elif post_type == "reel":
        notification_type = "channel_video"
        title = f"Новое видео в канале {channel.name}"
        body = post_title or "Новое видео"
    
    # Создаем уведомления для всех подписчиков
    notifications = []
    push_service = get_push_service()
    
    for subscriber in subscribers:
        # Проверяем настройки уведомлений пользователя (TODO: добавить проверку)
        # Пока отправляем всем
        
        notification = Notification(
            user_id=subscriber.user_id,
            type=notification_type,
            entity_type="channel",
            entity_id=channel_id,
            actor_id=author_id,
            title=title,
            body=body,
            data={
                "channel_id": channel_id,
                "channel_name": channel.name,
                "post_id": post_id,
                "post_type": post_type,
            },
            is_read=False,
            created_at=datetime.utcnow()
        )
        notifications.append(notification)
    
    # Массовое добавление уведомлений
    if notifications:
        db.bulk_save_objects(notifications)
        db.commit()
        
        # Отправляем push-уведомления
        if push_service.enabled:
            try:
                for notification in notifications:
                    push_service.send_notification(
                        user_id=notification.user_id,
                        title=notification.title,
                        body=notification.body,
                        data=notification.data
                    )
            except Exception as e:
                import logging
                logger = logging.getLogger(__name__)
                logger.warning(f"Error sending push notifications: {e}", exc_info=True)


def send_channel_announcement(
    db: Session,
    channel_id: int,
    announcement_text: str,
    author_id: int
):
    """
    Отправить объявление подписчикам канала
    """
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        return
    
    subscribers = db.query(ChannelMember).filter(
        ChannelMember.channel_id == channel_id,
        ChannelMember.user_id != author_id
    ).all()
    
    if not subscribers:
        return
    
    notifications = []
    push_service = get_push_service()
    
    for subscriber in subscribers:
        notification = Notification(
            user_id=subscriber.user_id,
            type="channel_announcement",
            entity_type="channel",
            entity_id=channel_id,
            actor_id=author_id,
            title=f"Объявление от {channel.name}",
            body=announcement_text,
            data={
                "channel_id": channel_id,
                "channel_name": channel.name,
            },
            is_read=False,
            created_at=datetime.utcnow()
        )
        notifications.append(notification)
    
    if notifications:
        db.bulk_save_objects(notifications)
        db.commit()
        
        if push_service.enabled:
            try:
                for notification in notifications:
                    push_service.send_notification(
                        user_id=notification.user_id,
                        title=notification.title,
                        body=notification.body,
                        data=notification.data
                    )
            except Exception as e:
                import logging
                logger = logging.getLogger(__name__)
                logger.warning(f"Error sending push notifications: {e}", exc_info=True)

