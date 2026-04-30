"""
Сервис для отправки push уведомлений через FCM/APNs
"""
import os
import json
import logging
from typing import Optional, Dict, Any
from sqlalchemy.orm import Session
from app.models.user import User
from app.models.notification import Notification
from app.core.config import settings

logger = logging.getLogger(__name__)

# Firebase Admin SDK
_firebase_app = None
try:
    import firebase_admin
    from firebase_admin import credentials, messaging
    FIREBASE_AVAILABLE = True
except ImportError:
    FIREBASE_AVAILABLE = False
    logger.warning("firebase-admin not installed. Push notifications will be disabled.")


class PushService:
    """Сервис для отправки push уведомлений через Firebase (FCM для Android и APNs для iOS)"""
    
    def __init__(self):
        self.enabled = False
        self._initialize_firebase()
    
    def _initialize_firebase(self):
        """Инициализировать Firebase Admin SDK"""
        global _firebase_app
        
        if not FIREBASE_AVAILABLE:
            logger.warning("Firebase Admin SDK not available")
            return
        
        if not settings.FIREBASE_ENABLED:
            logger.info("Firebase disabled in settings")
            return
        
        try:
            # Проверяем, не инициализирован ли уже Firebase
            try:
                _firebase_app = firebase_admin.get_app()
                logger.info("Firebase already initialized")
                self.enabled = True
                return
            except ValueError:
                # Firebase не инициализирован, продолжаем
                pass
            
            # Инициализируем Firebase
            if settings.FIREBASE_CREDENTIALS_PATH:
                # Загружаем credentials из файла
                if os.path.exists(settings.FIREBASE_CREDENTIALS_PATH):
                    cred = credentials.Certificate(settings.FIREBASE_CREDENTIALS_PATH)
                    _firebase_app = firebase_admin.initialize_app(cred)
                    self.enabled = True
                    logger.info("Firebase initialized from credentials file")
                else:
                    logger.error(f"Firebase credentials file not found: {settings.FIREBASE_CREDENTIALS_PATH}")
            elif os.getenv("FIREBASE_CREDENTIALS_JSON"):
                # Загружаем credentials из переменной окружения (JSON строка)
                cred_dict = json.loads(os.getenv("FIREBASE_CREDENTIALS_JSON"))
                cred = credentials.Certificate(cred_dict)
                _firebase_app = firebase_admin.initialize_app(cred)
                self.enabled = True
                logger.info("Firebase initialized from environment variable")
            else:
                # Пытаемся использовать Application Default Credentials (для GCP)
                try:
                    _firebase_app = firebase_admin.initialize_app()
                    self.enabled = True
                    logger.info("Firebase initialized with Application Default Credentials")
                except Exception as e:
                    logger.warning(f"Failed to initialize Firebase with ADC: {e}")
                    
        except Exception as e:
            logger.error(f"Failed to initialize Firebase: {e}")
            self.enabled = False
    
    def send_push_notification(
        self,
        user: User,
        notification: Notification,
        data: Optional[Dict[str, Any]] = None
    ) -> bool:
        """
        Отправить push уведомление пользователю через Firebase (FCM для Android, APNs для iOS)
        
        Args:
            user: Пользователь, которому отправляется уведомление
            notification: Объект уведомления из БД
            data: Дополнительные данные для уведомления
            
        Returns:
            True если отправка успешна, False в противном случае
        """
        if not self.enabled:
            logger.debug("Push notifications not enabled, skipping")
            return False
        
        if not user.fcm_token:
            logger.debug(f"User {user.id} has no FCM token")
            return False
        
        if not FIREBASE_AVAILABLE:
            logger.warning("Firebase Admin SDK not available")
            return False
        
        try:
            # Подготавливаем данные уведомления
            notification_data = {
                "type": notification.type,
                "entity_type": notification.entity_type or "",
                "entity_id": str(notification.entity_id) if notification.entity_id else "",
                "actor_id": str(notification.actor_id) if notification.actor_id else "",
            }
            
            # Добавляем дополнительные данные
            if data:
                notification_data.update({k: str(v) for k, v in data.items()})
            
            # Определяем платформу для настройки уведомления
            platform = user.device_platform or "android"  # По умолчанию Android
            
            # Создаем сообщение
            message = messaging.Message(
                notification=messaging.Notification(
                    title=notification.title,
                    body=notification.body or notification.title,
                ),
                data=notification_data,
                token=user.fcm_token,
                # Настройки для iOS (APNs)
                apns=messaging.APNSConfig(
                    payload=messaging.APNSPayload(
                        aps=messaging.Aps(
                            alert=messaging.ApsAlert(
                                title=notification.title,
                                body=notification.body or notification.title,
                            ),
                            badge=1,  # Увеличиваем badge на 1
                            sound="default",
                            content_available=True,  # Для фоновых уведомлений
                        ),
                    ),
                    headers={
                        "apns-priority": "10",  # Высокий приоритет
                    },
                ),
                # Настройки для Android (FCM)
                android=messaging.AndroidConfig(
                    priority="high",
                    notification=messaging.AndroidNotification(
                        title=notification.title,
                        body=notification.body or notification.title,
                        sound="default",
                        channel_id="default",  # Канал уведомлений Android
                        click_action="FLUTTER_NOTIFICATION_CLICK",  # Для Flutter
                    ),
                ),
            )
            
            # Отправляем уведомление
            response = messaging.send(message)
            logger.info(f"Push notification sent to user {user.id} (platform: {platform}), message ID: {response}")
            return True
            
        except messaging.UnregisteredError:
            # Токен больше не действителен, нужно удалить его из БД
            logger.warning(f"FCM token for user {user.id} is invalid, removing from database")
            self.remove_invalid_token(user.id)
            return False
        except messaging.InvalidArgumentError as e:
            logger.error(f"Invalid argument for push notification to user {user.id}: {e}")
            return False
        except Exception as e:
            logger.error(f"Failed to send push notification to user {user.id}: {e}", exc_info=True)
            return False
    
    def send_batch_push_notifications(
        self,
        notifications: list[tuple[User, Notification]],
        data: Optional[Dict[str, Any]] = None
    ) -> int:
        """
        Отправить батч push уведомлений через Firebase (до 500 за раз)
        
        Args:
            notifications: Список кортежей (user, notification)
            data: Дополнительные данные для всех уведомлений
            
        Returns:
            Количество успешно отправленных уведомлений
        """
        if not self.enabled or not FIREBASE_AVAILABLE:
            return 0
        
        if len(notifications) == 0:
            return 0
        
        # Firebase поддерживает до 500 сообщений за раз
        batch_size = 500
        success_count = 0
        
        for i in range(0, len(notifications), batch_size):
            batch = notifications[i:i + batch_size]
            messages = []
            
            for user, notification in batch:
                if not user.fcm_token:
                    continue
                
                # Подготавливаем данные
                notification_data = {
                    "type": notification.type,
                    "entity_type": notification.entity_type or "",
                    "entity_id": str(notification.entity_id) if notification.entity_id else "",
                    "actor_id": str(notification.actor_id) if notification.actor_id else "",
                }
                
                if data:
                    notification_data.update({k: str(v) for k, v in data.items()})
                
                platform = user.device_platform or "android"
                
                # Создаем сообщение
                message = messaging.Message(
                    notification=messaging.Notification(
                        title=notification.title,
                        body=notification.body or notification.title,
                    ),
                    data=notification_data,
                    token=user.fcm_token,
                    apns=messaging.APNSConfig(
                        payload=messaging.APNSPayload(
                            aps=messaging.Aps(
                                alert=messaging.ApsAlert(
                                    title=notification.title,
                                    body=notification.body or notification.title,
                                ),
                                badge=1,
                                sound="default",
                                content_available=True,
                            ),
                        ),
                        headers={"apns-priority": "10"},
                    ),
                    android=messaging.AndroidConfig(
                        priority="high",
                        notification=messaging.AndroidNotification(
                            title=notification.title,
                            body=notification.body or notification.title,
                            sound="default",
                            channel_id="default",
                            click_action="FLUTTER_NOTIFICATION_CLICK",
                        ),
                    ),
                )
                messages.append(message)
            
            if messages:
                try:
                    # Отправляем батч
                    response = messaging.send_all(messages)
                    success_count += response.success_count
                    logger.info(f"Sent batch: {response.success_count} successful, {response.failure_count} failed")
                    
                    # Обрабатываем ошибки
                    invalid_token_user_ids = []
                    if response.failure_count > 0:
                        for idx, resp in enumerate(response.responses):
                            if not resp.success:
                                exception = resp.exception
                                logger.warning(f"Failed to send message {idx}: {exception}")
                                
                                # Если токен недействителен, добавляем в список для удаления
                                if isinstance(exception, messaging.UnregisteredError):
                                    user, _ = batch[idx]
                                    if user:
                                        invalid_token_user_ids.append(user.id)
                    
                    # Удаляем недействительные токены
                    if invalid_token_user_ids:
                        from app.core.database import SessionLocal
                        db = SessionLocal()
                        try:
                            self.remove_invalid_tokens_batch(invalid_token_user_ids, db)
                        finally:
                            db.close()
                                
                except Exception as e:
                    logger.error(f"Failed to send batch push notifications: {e}", exc_info=True)
        
        return success_count
    
    def remove_invalid_token(self, user_id: int) -> bool:
        """
        Удалить недействительный FCM токен из БД
        
        Args:
            user_id: ID пользователя
            
        Returns:
            True если токен удален, False в противном случае
        """
        try:
            from app.core.database import get_db
            from sqlalchemy.orm import Session
            
            # Получаем сессию БД (в реальности лучше передавать db как параметр)
            # Для упрощения используем глобальную сессию или создаем новую
            from app.core.database import SessionLocal
            db = SessionLocal()
            
            try:
                user = db.query(User).filter(User.id == user_id).first()
                if user and user.fcm_token:
                    user.fcm_token = None
                    db.commit()
                    logger.info(f"Removed invalid FCM token for user {user_id}")
                    return True
                return False
            finally:
                db.close()
                
        except Exception as e:
            logger.error(f"Failed to remove invalid FCM token for user {user_id}: {e}", exc_info=True)
            return False
    
    def remove_invalid_tokens_batch(self, user_ids: list[int], db: Session) -> int:
        """
        Удалить недействительные FCM токены для списка пользователей
        
        Args:
            user_ids: Список ID пользователей
            db: Сессия БД
            
        Returns:
            Количество удаленных токенов
        """
        if not user_ids:
            return 0
        
        try:
            users = db.query(User).filter(
                User.id.in_(user_ids),
                User.fcm_token.isnot(None)
            ).all()
            
            removed_count = 0
            for user in users:
                user.fcm_token = None
                removed_count += 1
            
            db.commit()
            logger.info(f"Removed {removed_count} invalid FCM tokens")
            return removed_count
            
        except Exception as e:
            logger.error(f"Failed to remove invalid FCM tokens: {e}", exc_info=True)
            db.rollback()
            return 0
    
    def cleanup_invalid_tokens(self, db: Session, batch_size: int = 100) -> int:
        """
        Автоматическая очистка недействительных FCM токенов
        
        Проверяет токены пользователей, используя validate_token для каждого токена,
        и удаляет недействительные токены.
        
        Args:
            db: Сессия БД
            batch_size: Размер батча для обработки
            
        Returns:
            Количество удаленных токенов
        """
        if not self.enabled or not FIREBASE_AVAILABLE:
            logger.debug("Push service not enabled, skipping token cleanup")
            return 0
        
        try:
            # Получаем пользователей с FCM токенами
            users_with_tokens = db.query(User).filter(
                User.fcm_token.isnot(None)
            ).limit(batch_size).all()
            
            if not users_with_tokens:
                logger.debug("No users with FCM tokens found")
                return 0
            
            invalid_token_user_ids = []
            
            # Проверяем каждый токен
            for user in users_with_tokens:
                if not self.validate_token(user.fcm_token):
                    invalid_token_user_ids.append(user.id)
                    logger.debug(f"Token for user {user.id} is invalid")
            
            # Удаляем недействительные токены
            if invalid_token_user_ids:
                removed_count = self.remove_invalid_tokens_batch(invalid_token_user_ids, db)
                logger.info(f"Cleaned up {removed_count} invalid FCM tokens")
                return removed_count
            
            return 0
            
        except Exception as e:
            logger.error(f"Failed to cleanup invalid FCM tokens: {e}", exc_info=True)
            return 0
    
    def validate_token(self, fcm_token: str) -> bool:
        """
        Проверить валидность FCM токена
        
        Использует dry_run=True для проверки токена без фактической отправки уведомления.
        
        Args:
            fcm_token: FCM токен для проверки
            
        Returns:
            True если токен валиден, False в противном случае
        """
        if not self.enabled or not FIREBASE_AVAILABLE:
            return False
        
        if not fcm_token:
            return False
        
        try:
            # Создаем тестовое сообщение (data-only, без notification)
            # dry_run=True проверяет токен без фактической отправки
            test_message = messaging.Message(
                data={"test": "token_validation"},
                token=fcm_token,
            )
            # dry_run=True проверяет валидность токена без отправки
            messaging.send(test_message, dry_run=True)
            return True
        except messaging.UnregisteredError:
            # Токен не зарегистрирован (приложение удалено, токен устарел)
            return False
        except messaging.InvalidArgumentError:
            # Неверный формат токена
            return False
        except messaging.SenderIdMismatchError:
            # Токен от другого проекта
            return False
        except Exception as e:
            # Другие ошибки - считаем токен невалидным для безопасности
            logger.warning(f"Error validating token: {e}")
            return False


# Глобальный экземпляр сервиса
_push_service: Optional[PushService] = None


def get_push_service() -> PushService:
    """Получить глобальный экземпляр PushService"""
    global _push_service
    if _push_service is None:
        _push_service = PushService()
    return _push_service

