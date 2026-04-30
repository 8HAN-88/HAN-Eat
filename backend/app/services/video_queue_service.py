"""
Сервис для работы с очередью обработки видео
"""
import json
import logging
from typing import Dict, Optional
from app.core.redis_client import redis_client
from app.models.video_processing import VideoProcessing
from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)


class VideoQueueService:
    """Сервис для управления очередью обработки видео"""
    
    QUEUE_KEY = "video:processing:queue"
    STATUS_KEY_PREFIX = "video:status:"
    
    @staticmethod
    def enqueue_video_processing(
        db: Session,
        upload_id: str,
        file_key: str,
        user_id: int
    ) -> VideoProcessing:
        """
        Добавить видео в очередь обработки
        
        Args:
            db: Database session
            upload_id: ID загрузки
            file_key: S3 ключ файла
            user_id: ID пользователя
            
        Returns:
            VideoProcessing объект
        """
        # Создаем запись в БД
        video_processing = VideoProcessing(
            upload_id=upload_id,
            file_key=file_key,
            user_id=user_id,
            status="pending"
        )
        db.add(video_processing)
        db.commit()
        db.refresh(video_processing)
        
        # Добавляем в очередь Redis
        task_data = {
            "upload_id": upload_id,
            "file_key": file_key,
            "user_id": user_id,
            "processing_id": video_processing.id
        }
        
        try:
            redis_client.lpush(VideoQueueService.QUEUE_KEY, json.dumps(task_data))
            logger.info(f"Video processing task enqueued: {upload_id}")
        except Exception as e:
            logger.error(f"Failed to enqueue video processing: {e}")
            # Обновляем статус на failed
            video_processing.status = "failed"
            video_processing.error_message = f"Failed to enqueue: {str(e)}"
            db.commit()
        
        return video_processing
    
    @staticmethod
    def dequeue_video_processing() -> Optional[Dict]:
        """
        Получить следующую задачу из очереди
        
        Returns:
            Dict с данными задачи или None
        """
        try:
            task_json = redis_client.rpop(VideoQueueService.QUEUE_KEY)
            if task_json:
                return json.loads(task_json)
        except Exception as e:
            logger.error(f"Failed to dequeue video processing: {e}")
        return None
    
    @staticmethod
    def update_processing_status(
        upload_id: str,
        status: str,
        progress: Optional[float] = None,
        error_message: Optional[str] = None
    ):
        """
        Обновить статус обработки в Redis (для быстрого доступа)
        
        Args:
            upload_id: ID загрузки
            status: новый статус
            progress: прогресс (0-100)
            error_message: сообщение об ошибке
        """
        status_key = f"{VideoQueueService.STATUS_KEY_PREFIX}{upload_id}"
        status_data = {
            "status": status,
            "progress": progress or 0.0,
            "error": error_message
        }
        
        try:
            redis_client.setex(
                status_key,
                3600,  # TTL 1 час
                json.dumps(status_data)
            )
        except Exception as e:
            logger.error(f"Failed to update processing status: {e}")
    
    @staticmethod
    def get_processing_status(upload_id: str) -> Optional[Dict]:
        """
        Получить статус обработки из Redis
        
        Args:
            upload_id: ID загрузки
            
        Returns:
            Dict со статусом или None
        """
        status_key = f"{VideoQueueService.STATUS_KEY_PREFIX}{upload_id}"
        try:
            status_json = redis_client.get(status_key)
            if status_json:
                return json.loads(status_json)
        except Exception as e:
            logger.error(f"Failed to get processing status: {e}")
        return None

