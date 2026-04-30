"""
Сервис для работы с уведомлениями
"""
from sqlalchemy.orm import Session
from datetime import datetime
from typing import Optional, Dict, Any
from app.models.notification import Notification
from app.models.user import User


class NotificationService:
    """Сервис для создания и отправки уведомлений"""
    
    def __init__(self, db: Session):
        self.db = db
    
    def create_notification(
        self,
        user_id: int,
        type: str,
        title: str,
        body: Optional[str] = None,
        entity_type: Optional[str] = None,
        entity_id: Optional[int] = None,
        actor_id: Optional[int] = None,
        data: Optional[Dict[str, Any]] = None
    ) -> Notification:
        """Создать уведомление"""
        notification = Notification(
            user_id=user_id,
            type=type,
            title=title,
            body=body,
            entity_type=entity_type,
            entity_id=entity_id,
            actor_id=actor_id,
            data=data or {}
        )
        
        self.db.add(notification)
        # Не коммитим здесь, чтобы можно было батчить уведомления
        
        # Отправляем push-уведомление (если есть FCM токен)
        self._send_push_notification(notification)
        
        return notification
    
    def notify_like(
        self,
        post_author_id: int,
        liker_id: int,
        post_id: int,
        liker_name: str
    ):
        """Уведомить о лайке поста"""
        # Не уведомляем, если пользователь лайкнул свой пост
        if post_author_id == liker_id:
            return
        
        notification = self.create_notification(
            user_id=post_author_id,
            type="like",
            title=f"{liker_name} лайкнул(а) ваш пост",
            body=None,
            entity_type="post",
            entity_id=post_id,
            actor_id=liker_id,
            data={
                "post_id": post_id,
                "action": "like"
            }
        )
        
        return notification
    
    def notify_comment(
        self,
        post_author_id: int,
        commenter_id: int,
        post_id: int,
        comment_id: int,
        commenter_name: str,
        comment_text: str
    ):
        """Уведомить о комментарии к посту"""
        # Не уведомляем, если пользователь прокомментировал свой пост
        if post_author_id == commenter_id:
            return
        
        # Обрезаем текст комментария для уведомления
        preview = comment_text[:100] + "..." if len(comment_text) > 100 else comment_text
        
        notification = self.create_notification(
            user_id=post_author_id,
            type="comment",
            title=f"{commenter_name} прокомментировал(а) ваш пост",
            body=preview,
            entity_type="post",
            entity_id=post_id,
            actor_id=commenter_id,
            data={
                "post_id": post_id,
                "comment_id": comment_id,
                "action": "comment"
            }
        )
        
        return notification
    
    def notify_follow(
        self,
        followee_id: int,
        follower_id: int,
        follower_name: str
    ):
        """Уведомить о новой подписке"""
        notification = self.create_notification(
            user_id=followee_id,
            type="follow",
            title=f"{follower_name} подписался(ась) на вас",
            body=None,
            entity_type="user",
            entity_id=follower_id,
            actor_id=follower_id,
            data={
                "user_id": follower_id,
                "action": "follow"
            }
        )
        
        return notification
    
    def notify_repost(
        self,
        post_author_id: int,
        reposter_id: int,
        post_id: int,
        reposter_name: str
    ):
        """Уведомить о репосте"""
        # Не уведомляем, если пользователь репостнул свой пост
        if post_author_id == reposter_id:
            return
        
        notification = self.create_notification(
            user_id=post_author_id,
            type="repost",
            title=f"{reposter_name} репостнул(а) ваш пост",
            body=None,
            entity_type="post",
            entity_id=post_id,
            actor_id=reposter_id,
            data={
                "post_id": post_id,
                "action": "repost"
            }
        )
        
        return notification
    
    def notify_mention(
        self,
        mentioned_user_id: int,
        mentioner_id: int,
        post_id: int,
        mentioner_name: str
    ):
        """Уведомить об упоминании"""
        notification = self.create_notification(
            user_id=mentioned_user_id,
            type="mention",
            title=f"{mentioner_name} упомянул(а) вас",
            body=None,
            entity_type="post",
            entity_id=post_id,
            actor_id=mentioner_id,
            data={
                "post_id": post_id,
                "action": "mention"
            }
        )
        
        return notification
    
    def _send_push_notification(self, notification: Notification):
        """Отправить push-уведомление через FCM/APNs"""
        try:
            # Получаем пользователя
            user = self.db.query(User).filter(User.id == notification.user_id).first()
            if not user or not user.fcm_token:
                return
            
            # Проверяем настройки уведомлений
            from app.models.notification_preferences import NotificationPreferences
            prefs = self.db.query(NotificationPreferences).filter(
                NotificationPreferences.user_id == user.id
            ).first()
            
            # Если настроек нет, используем дефолтные (все включено)
            if prefs:
                # Проверяем общий переключатель push
                if not prefs.push_enabled:
                    return
                
                # Проверяем конкретный тип уведомления
                notification_type = notification.type.lower()
                if notification_type == "like" and not prefs.likes_enabled:
                    return
                elif notification_type == "comment" and not prefs.comments_enabled:
                    return
                elif notification_type == "follow" and not prefs.follows_enabled:
                    return
                elif notification_type == "repost" and not prefs.reposts_enabled:
                    return
                elif notification_type == "mention" and not prefs.mentions_enabled:
                    return
                elif notification_type == "system" and not prefs.system_enabled:
                    return
            
            # Импортируем PushService
            from app.services.push_service import get_push_service
            
            push_service = get_push_service()
            push_service.send_push_notification(
                user=user,
                notification=notification,
                data=notification.data
            )
        except Exception as e:
            # Логируем ошибку, но не прерываем создание уведомления
            import logging
            logger = logging.getLogger(__name__)
            logger.error(f"Failed to send push notification: {e}")

