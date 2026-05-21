"""
Сервис для работы с медиа (S3, обработка, транс-кодинг)
"""
import boto3
import uuid
import hashlib
import re
from datetime import datetime, timedelta
from typing import Dict, Optional
from botocore.config import Config
from botocore.exceptions import ClientError
from app.core.config import settings


class MediaService:
    """Сервис для работы с медиа файлами"""
    
    def __init__(self):
        self.s3_client = self._init_s3_client()
        self.bucket = settings.S3_BUCKET
        self.cdn_url = settings.CDN_URL
    
    def _init_s3_client(self):
        """Инициализация S3 клиента"""
        config = Config(
            region_name=settings.S3_REGION,
            signature_version='s3v4'
        )
        
        if settings.S3_ACCESS_KEY and settings.S3_SECRET_KEY:
            return boto3.client(
                's3',
                endpoint_url=settings.S3_ENDPOINT_URL,
                aws_access_key_id=settings.S3_ACCESS_KEY,
                aws_secret_access_key=settings.S3_SECRET_KEY,
                config=config
            )
        else:
            # Для локальной разработки без реального S3
            # В продакшене должны быть настроены credentials
            return None
    
    def generate_presigned_url(
        self,
        file_type: str,
        content_type: str,
        file_size: int,
        user_id: int
    ) -> Dict[str, str]:
        """
        Генерация presigned URL для загрузки файла
        
        Args:
            file_type: image | video
            content_type: MIME type (image/jpeg, video/mp4, etc.)
            file_size: размер файла в байтах
            
        Returns:
            {
                "upload_id": "...",
                "upload_url": "https://...",
                "file_key": "uploads/user_123/abc123.jpg",
                "expires_in": 3600
            }
        """
        # Валидация типа файла
        if file_type == "image":
            if not any(content_type.lower().endswith(f"/{ext}") for ext in settings.ALLOWED_IMAGE_TYPES):
                raise ValueError(f"Unsupported image type: {content_type}")
            max_size = settings.MAX_IMAGE_SIZE_MB * 1024 * 1024
        elif file_type == "video":
            if not any(content_type.lower().endswith(f"/{ext}") for ext in settings.ALLOWED_VIDEO_TYPES):
                raise ValueError(f"Unsupported video type: {content_type}")
            max_size = settings.MAX_VIDEO_SIZE_MB * 1024 * 1024
        else:
            raise ValueError(f"Invalid file_type: {file_type}. Must be 'image' or 'video'")
        
        # Проверка размера
        if file_size > max_size:
            raise ValueError(f"File size exceeds maximum: {max_size / (1024*1024):.1f}MB")
        
        # Генерируем уникальный ключ файла
        file_extension = content_type.split('/')[-1]
        if file_extension not in ['jpeg', 'jpg', 'png', 'webp', 'mp4', 'mov', 'avi']:
            file_extension = 'jpg' if file_type == 'image' else 'mp4'
        
        upload_id = str(uuid.uuid4())
        timestamp = datetime.utcnow().strftime("%Y/%m/%d")
        file_key = f"uploads/user_{user_id}/{timestamp}/{upload_id}.{file_extension}"
        
        # Если S3 не настроен (локальная разработка), возвращаем mock URL
        if not self.s3_client:
            base = settings.API_PUBLIC_BASE_URL.rstrip("/")
            return {
                "upload_id": upload_id,
                "upload_url": f"{base}/api/v1/uploads/mock/{upload_id}",
                "file_key": file_key,
                "expires_in": 3600,
                "cdn_url": f"{self.cdn_url}/{file_key}"
            }
        
        # Генерируем presigned URL
        try:
            presigned_url = self.s3_client.generate_presigned_url(
                'put_object',
                Params={
                    'Bucket': self.bucket,
                    'Key': file_key,
                    'ContentType': content_type,
                    'ContentLength': file_size,
                },
                ExpiresIn=3600  # 1 час
            )
            
            return {
                "upload_id": upload_id,
                "upload_url": presigned_url,
                "file_key": file_key,
                "expires_in": 3600,
                "cdn_url": f"{self.cdn_url}/{file_key}"
            }
        except ClientError as e:
            raise Exception(f"Failed to generate presigned URL: {str(e)}")

    @staticmethod
    def _user_id_from_file_key(file_key: str) -> Optional[int]:
        """Ключ вида uploads/user_123/... → 123."""
        m = re.search(r"uploads/user_(\d+)/", file_key)
        if not m:
            return None
        try:
            return int(m.group(1))
        except ValueError:
            return None

    def complete_upload(
        self,
        upload_id: str,
        file_key: str,
        file_type: str,
        user_id: Optional[int] = None
    ) -> Dict[str, str]:
        """
        Завершение загрузки (после того, как клиент загрузил файл)
        
        Для видео запускает обработку (транс-кодинг, thumbnail)
        Для изображений может запустить оптимизацию
        
        Returns:
            {
                "status": "completed",
                "url": "https://cdn.../file.jpg",
                "thumbnail_url": "https://cdn.../thumb.jpg" (для видео),
                "processing": false
            }
        """
        if not self.s3_client:
            # Mock для локальной разработки
            # Используем локальный URL вместо CDN
            # file_key имеет формат: uploads/user_2/2025/12/10/uuid.jpg
            base = settings.API_PUBLIC_BASE_URL.rstrip("/")
            local_url = f"{base}/api/v1/uploads/file/{file_key}"
            return {
                "status": "completed",
                "url": local_url,
                "thumbnail_url": None,
                "processing": False
            }
        
        # Проверяем, что файл существует в S3
        try:
            self.s3_client.head_object(Bucket=self.bucket, Key=file_key)
        except ClientError as e:
            if e.response['Error']['Code'] == '404':
                raise ValueError(f"File not found: {file_key}")
            raise
        
        url = f"{self.cdn_url}/{file_key}"

        effective_user_id = user_id if user_id is not None else self._user_id_from_file_key(file_key)

        # Для видео запускаем обработку
        if file_type == "video":
            # Очередь видео ставится в API /uploads/complete (есть db и current_user).
            # Создаем запись обработки и добавляем в очередь
            # Для этого нужна db session, но здесь её нет
            # Поэтому возвращаем статус "processing" и обработка будет запущена асинхронно
            return {
                "status": "processing",
                "url": url,  # Временный URL исходного файла
                "thumbnail_url": None,
                "processing": True,
                "upload_id": upload_id
            }
        
        # Для изображений запускаем обработку (оптимизация, ресайз)
        # Импортируем здесь, чтобы избежать circular imports
        from app.services.image_queue_service import ImageQueueService
        
        # Создаем запись обработки и добавляем в очередь
        # Для этого нужна db session, но здесь её нет
        # Поэтому возвращаем статус "processing" и обработка будет запущена асинхронно
        if effective_user_id:
            return {
                "status": "processing",
                "url": url,  # Временный URL исходного файла
                "thumbnail_url": None,
                "processing": True,
                "upload_id": upload_id
            }
        
        # Если user_id не передан, возвращаем как есть (для обратной совместимости)
        return {
            "status": "completed",
            "url": url,
            "thumbnail_url": None,
            "processing": False
        }
    
    def get_upload_status(self, upload_id: str) -> Dict[str, any]:
        """
        Получить статус обработки загрузки
        
        Returns:
            {
                "status": "processing" | "completed" | "failed",
                "progress": 0-100,
                "url": "...",
                "hls_url": "...",
                "thumbnail_url": "..."
            }
        """
        from app.services.video_queue_service import VideoQueueService
        from app.core.database import get_db
        from app.models.video_processing import VideoProcessing
        
        # Сначала проверяем Redis (быстрый доступ)
        redis_status = VideoQueueService.get_processing_status(upload_id)
        
        # Затем проверяем БД (более полная информация)
        # Для этого нужна db session, но здесь её нет
        # В реальности нужно передавать db session или использовать dependency injection
        
        if redis_status:
            return {
                "status": redis_status.get("status", "pending"),
                "progress": redis_status.get("progress", 0.0),
                "url": None,
                "hls_url": None,
                "thumbnail_url": None
            }
        
        # Если нет в Redis, возвращаем pending
        return {
            "status": "pending",
            "progress": 0.0,
            "url": None,
            "hls_url": None,
            "thumbnail_url": None
        }
    
    def delete_file(self, file_key: str) -> bool:
        """Удалить файл из S3"""
        if not self.s3_client:
            return True  # Mock
        
        try:
            self.s3_client.delete_object(Bucket=self.bucket, Key=file_key)
            return True
        except ClientError:
            return False
