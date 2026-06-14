"""
Сервис для работы с медиа (S3, обработка, транс-кодинг)
"""
import logging
import boto3
import uuid
import hashlib
import re
from datetime import datetime, timedelta
from typing import Dict, Optional
from botocore.config import Config
from botocore.exceptions import ClientError
from app.core.config import settings

logger = logging.getLogger(__name__)

# iOS галерея/камера отдаёт .mov как video/quicktime, не video/mov.
_VIDEO_MIME_ALIASES = frozenset(
    {
        "video/quicktime",
        "video/x-quicktime",
        "video/x-msvideo",
    }
)


def _is_allowed_video_content_type(content_type: str) -> bool:
    ct = content_type.lower().strip()
    if ct in _VIDEO_MIME_ALIASES:
        return True
    return any(ct.endswith(f"/{ext}") for ext in settings.ALLOWED_VIDEO_TYPES)


def _video_extension_from_content_type(content_type: str) -> str:
    ct = content_type.lower().strip()
    if ct in ("video/quicktime", "video/x-quicktime"):
        return "mov"
    if ct in ("video/x-msvideo",) or ct.endswith("/avi"):
        return "avi"
    if ct.endswith("/mov"):
        return "mov"
    if ct.endswith("/mp4"):
        return "mp4"
    if ct.endswith("/webm"):
        return "webm"
    return "mp4"


class MediaService:
    """Сервис для работы с медиа файлами"""
    
    def __init__(self):
        self.bucket = settings.S3_BUCKET
        self.cdn_url = settings.CDN_URL
        self.s3_client = self._init_s3_client()
    
    def _init_s3_client(self):
        """Инициализация S3 клиента; при неверных ключах — загрузка через API (mock)."""
        config = Config(
            region_name=settings.S3_REGION,
            signature_version='s3v4'
        )
        
        if not settings.S3_ACCESS_KEY or not settings.S3_SECRET_KEY:
            return None

        client = boto3.client(
            's3',
            endpoint_url=settings.S3_ENDPOINT_URL or None,
            aws_access_key_id=settings.S3_ACCESS_KEY,
            aws_secret_access_key=settings.S3_SECRET_KEY,
            config=config,
        )
        try:
            client.head_bucket(Bucket=self.bucket)
        except ClientError as e:
            code = e.response.get("Error", {}).get("Code", "")
            logger.warning(
                "S3 недоступен (%s): %s — загрузки пойдут через API /uploads/mock",
                code,
                e.response.get("Error", {}).get("Message", str(e)),
            )
            return None
        except Exception as e:
            logger.warning("S3 head_bucket failed: %s — using API upload", e)
            return None
        return client

    @property
    def uses_api_upload(self) -> bool:
        """Файлы принимаются на бэкенд, а не по presigned URL в S3."""
        return self.s3_client is None
    
    def generate_presigned_url(
        self,
        file_type: str,
        content_type: str,
        file_size: int,
        user_id: int,
        prefer_api: bool = False,
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
        max_size: Optional[int] = None
        if file_type == "image":
            if not any(content_type.lower().endswith(f"/{ext}") for ext in settings.ALLOWED_IMAGE_TYPES):
                raise ValueError(f"Unsupported image type: {content_type}")
            max_size = settings.MAX_IMAGE_SIZE_MB * 1024 * 1024
        elif file_type == "video":
            if not _is_allowed_video_content_type(content_type):
                raise ValueError(f"Unsupported video type: {content_type}")
            if settings.MAX_VIDEO_SIZE_MB > 0:
                max_size = settings.MAX_VIDEO_SIZE_MB * 1024 * 1024
        elif file_type == "audio":
            if not any(content_type.lower().endswith(f"/{ext}") for ext in settings.ALLOWED_AUDIO_TYPES):
                raise ValueError(f"Unsupported audio type: {content_type}")
            max_size = settings.MAX_AUDIO_SIZE_MB * 1024 * 1024
        elif file_type == "document":
            ct = content_type.lower()
            allowed = settings.ALLOWED_DOCUMENT_TYPES
            if not any(ext in ct for ext in allowed):
                raise ValueError(f"Unsupported document type: {content_type}")
            max_size = settings.MAX_DOCUMENT_SIZE_MB * 1024 * 1024
        else:
            raise ValueError(
                f"Invalid file_type: {file_type}. Must be 'image', 'video', 'audio' or 'document'"
            )
        
        if max_size is not None and file_size > max_size:
            raise ValueError(f"File size exceeds maximum: {max_size / (1024*1024):.1f}MB")
        
        # Генерируем уникальный ключ файла
        if file_type == "video":
            file_extension = _video_extension_from_content_type(content_type)
        else:
            file_extension = content_type.split("/")[-1]
            if file_extension not in [
                "jpeg",
                "jpg",
                "png",
                "webp",
                "mp4",
                "mov",
                "avi",
                "m4a",
                "aac",
                "mpeg",
                "mp3",
                "webm",
                "ogg",
                "pdf",
                "txt",
                "doc",
                "docx",
                "zip",
            ]:
                if file_type == "image":
                    file_extension = "jpg"
                elif file_type == "audio":
                    file_extension = "m4a"
                elif file_type == "document":
                    file_extension = "pdf"
                else:
                    file_extension = "mp4"
        
        upload_id = str(uuid.uuid4())
        timestamp = datetime.utcnow().strftime("%Y/%m/%d")
        file_key = f"uploads/user_{user_id}/{timestamp}/{upload_id}.{file_extension}"
        
        # Прямой S3 с телефона часто падает (TLS/сеть) — отдаём URL API.
        if prefer_api or not self.s3_client:
            from app.core.media_urls import public_base_url

            base = public_base_url()
            return {
                "upload_id": upload_id,
                "upload_url": f"{base}/api/v1/uploads/mock/{upload_id}",
                "file_key": file_key,
                "expires_in": 3600,
                "cdn_url": f"{self.cdn_url}/{file_key}",
                "upload_via": "api",
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
                "cdn_url": f"{self.cdn_url}/{file_key}",
                "upload_via": "s3",
            }
        except ClientError as e:
            logger.warning("presigned URL failed, fallback to API upload: %s", e)
            from app.core.media_urls import public_base_url

            base = public_base_url()
            return {
                "upload_id": upload_id,
                "upload_url": f"{base}/api/v1/uploads/mock/{upload_id}",
                "file_key": file_key,
                "expires_in": 3600,
                "cdn_url": f"{self.cdn_url}/{file_key}",
                "upload_via": "api",
            }

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
            from app.core.media_urls import normalize_media_url, public_base_url

            base = public_base_url()
            local_url = normalize_media_url(f"{base}/api/v1/uploads/file/{file_key}")
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

        if file_type == "audio":
            return {
                "status": "completed",
                "url": url,
                "thumbnail_url": None,
                "processing": False,
            }

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
