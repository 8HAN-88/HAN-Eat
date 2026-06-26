"""
API endpoints для загрузки медиа
"""
import json
import logging
from fastapi import APIRouter, Depends, HTTPException, status, Query, Request
from pydantic import BaseModel
from typing import Optional, Dict
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.config import settings
from app.core.redis_client import redis_client
from app.api.dependencies import get_current_user_required
from app.models.user import User
from app.services.media_service import MediaService

logger = logging.getLogger(__name__)

router = APIRouter()

# Временное хранилище для связи upload_id с file_key (для mock загрузки без S3).
# Дублируем в Redis (если доступен), иначе после перезапуска uvicorn клиент получает 404 на PUT /mock/{id}.
_upload_id_to_file_key: Dict[str, str] = {}
_MOCK_UPLOAD_REDIS_PREFIX = "upload:mock:"
_MOCK_UPLOAD_TTL_SEC = 7200
_CLIENT_UPLOAD_PREFIX = "upload:client:"
_CLIENT_UPLOAD_TTL_SEC = 3600


def _enforce_upload_rate_limit(user_id: int, action: str, limit: int) -> None:
    if not getattr(settings, "RATE_LIMIT_ENABLED", True):
        return
    from app.core.redis_client import REDIS_IS_STUB, get_redis

    if REDIS_IS_STUB:
        return
    key = f"rl:upload:{action}:{user_id}:minute"
    try:
        count = get_redis().incr(key)
        if count == 1:
            get_redis().expire(key, 60)
        if count > limit:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail={
                    "code": "UPLOAD_RATE_LIMIT_EXCEEDED",
                    "message": "Too many uploads. Please try again later.",
                },
                headers={"Retry-After": "60"},
            )
    except HTTPException:
        raise
    except Exception:
        return


def _client_upload_cache_key(user_id: int, client_upload_id: str) -> str:
    return f"{_CLIENT_UPLOAD_PREFIX}{user_id}:{client_upload_id}"


def _lookup_client_upload(user_id: int, client_upload_id: str) -> Optional[dict]:
    try:
        raw = redis_client.get(_client_upload_cache_key(user_id, client_upload_id))
        if raw:
            return json.loads(raw)
    except Exception as e:
        logger.debug("client upload cache lookup failed: %s", e)
    return None


def _store_client_upload(user_id: int, client_upload_id: str, payload: dict) -> None:
    try:
        redis_client.setex(
            _client_upload_cache_key(user_id, client_upload_id),
            _CLIENT_UPLOAD_TTL_SEC,
            json.dumps(payload),
        )
    except Exception as e:
        logger.debug("client upload cache store failed: %s", e)


def _remember_mock_upload(upload_id: str, file_key: str) -> None:
    _upload_id_to_file_key[upload_id] = file_key
    try:
        redis_client.setex(
            f"{_MOCK_UPLOAD_REDIS_PREFIX}{upload_id}",
            _MOCK_UPLOAD_TTL_SEC,
            file_key,
        )
    except Exception as e:
        logger.debug("mock upload: redis cache skipped: %s", e)


def _lookup_mock_file_key(upload_id: str) -> Optional[str]:
    fk = _upload_id_to_file_key.get(upload_id)
    if fk:
        return fk
    try:
        fk = redis_client.get(f"{_MOCK_UPLOAD_REDIS_PREFIX}{upload_id}")
        if fk:
            _upload_id_to_file_key[upload_id] = fk
            return fk
    except Exception as e:
        logger.debug("mock upload: redis lookup failed: %s", e)
    return None


class InitUploadRequest(BaseModel):
    file_type: str  # image | video | audio
    content_type: str  # image/jpeg, video/mp4, etc.
    file_size: int  # размер в байтах
    prefer_api: bool = False  # загрузка через API (надёжнее с мобильных)
    client_upload_id: Optional[str] = None  # идемпотентность при повторе клиента


class CompleteUploadRequest(BaseModel):
    upload_id: str
    file_key: str
    file_type: str  # image | video | audio


@router.post("/init")
async def init_upload(
    request: InitUploadRequest,
    current_user: User = Depends(get_current_user_required)
):
    """
    Инициализация загрузки (получить presigned URL)
    
    Клиент получает presigned URL и загружает файл напрямую в S3,
    затем отправляет file_key в запросе создания поста.
    """
    _enforce_upload_rate_limit(current_user.id, "init", 30)
    try:
        if request.client_upload_id:
            cached = _lookup_client_upload(
                current_user.id,
                request.client_upload_id,
            )
            if cached:
                return cached

        media_service = MediaService()
        result = media_service.generate_presigned_url(
            file_type=request.file_type,
            content_type=request.content_type,
            file_size=request.file_size,
            user_id=current_user.id,
            prefer_api=request.prefer_api,
        )
        # API-загрузка: запоминаем upload_id → file_key
        if result.get("upload_via") == "api":
            _remember_mock_upload(result["upload_id"], result["file_key"])
        if request.client_upload_id:
            _store_client_upload(current_user.id, request.client_upload_id, result)
        return result
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate upload URL: {str(e)}"
        )


@router.post("/complete")
async def complete_upload(
    request: CompleteUploadRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """
    Завершение загрузки
    
    Вызывается после того, как клиент загрузил файл по presigned URL.
    Для видео запускает обработку (транс-кодинг, thumbnail).
    Для изображений запускает оптимизацию (ресайз, сжатие).
    """
    from app.services.video_queue_service import VideoQueueService
    from app.services.image_queue_service import ImageQueueService
    from app.models.image_processing import ImageProcessing
    from app.models.video_processing import VideoProcessing
    
    _enforce_upload_rate_limit(current_user.id, "complete", 45)
    try:
        media_service = MediaService()
        result = media_service.complete_upload(
            upload_id=request.upload_id,
            file_key=request.file_key,
            file_type=request.file_type,
            user_id=current_user.id
        )

        if request.file_type == "image":
            existing = (
                db.query(ImageProcessing)
                .filter(
                    ImageProcessing.upload_id == request.upload_id,
                    ImageProcessing.user_id == current_user.id,
                )
                .first()
            )
            if existing:
                if existing.medium_url:
                    result["url"] = existing.medium_url
                elif existing.large_url:
                    result["url"] = existing.large_url
                elif existing.thumbnail_url:
                    result["url"] = existing.thumbnail_url
                result["status"] = "completed"
                result["processing"] = False
                result["upload_id"] = request.upload_id
                return result
        
        # Если это видео, добавляем в очередь обработки
        if request.file_type == "video":
            existing_video = (
                db.query(VideoProcessing)
                .filter(
                    VideoProcessing.upload_id == request.upload_id,
                    VideoProcessing.user_id == current_user.id,
                )
                .first()
            )
            if existing_video:
                if existing_video.mp4_720p_url:
                    result["url"] = existing_video.mp4_720p_url
                result["status"] = "completed"
                result["processing"] = False
                result["upload_id"] = request.upload_id
                return result
            video_processing = VideoQueueService.enqueue_video_processing(
                db=db,
                upload_id=request.upload_id,
                file_key=request.file_key,
                user_id=current_user.id
            )
            result["processing_id"] = video_processing.id
        
        # Если это изображение, обрабатываем синхронно для немедленного использования
        # (как в Telegram - изображения сразу доступны в правильном размере)
        elif request.file_type == "image":
            import os
            import tempfile
            import shutil
            
            # Создаем запись в БД
            image_processing = ImageQueueService.enqueue_image_processing(
                db=db,
                upload_id=request.upload_id,
                file_key=request.file_key,
                user_id=current_user.id
            )
            result["processing_id"] = image_processing.id
            
            # Синхронная обработка для немедленного использования
            # (полная обработка с WebP будет выполнена асинхронно)
            # Проверяем, доступен ли PIL для обработки
            try:
                from app.services.image_processing_service import ImageProcessingService
                processing_service = ImageProcessingService()
            except ImportError as e:
                # Если PIL не установлен, пропускаем синхронную обработку
                # Изображение будет обработано асинхронно воркером
                logger.warning(f"PIL not available, skipping sync image processing: {e}")
                logger.info("Image will be processed asynchronously by worker")
                return result
            
            try:
                processing_service = ImageProcessingService()
                temp_dir = tempfile.mkdtemp(prefix=f"image_sync_{request.upload_id}_")
                
                try:
                    # Скачиваем файл (для локальной разработки - читаем из файловой системы)
                    input_file_path = os.path.join(temp_dir, "input_image.jpg")
                    if not media_service.s3_client:
                        # Локальная разработка - файл уже на диске
                        file_path_full = os.path.join(os.getcwd(), request.file_key)
                        if os.path.exists(file_path_full):
                            shutil.copy2(file_path_full, input_file_path)
                        else:
                            # Если файл не найден, пропускаем синхронную обработку
                            logger.warning(f"File not found for sync processing: {request.file_key}")
                            return result
                    else:
                        # Production - скачиваем из S3
                        media_service.s3_client.download_file(
                            media_service.bucket,
                            request.file_key,
                            input_file_path
                        )
                    
                    # Обрабатываем изображение синхронно (создаем medium версию для немедленного использования)
                    output_dir = os.path.join(temp_dir, "output")
                    os.makedirs(output_dir, exist_ok=True)
                    
                    processed_files = processing_service.process_image(
                        input_file_path=input_file_path,
                        output_dir=output_dir,
                        upload_id=request.upload_id,
                        generate_webp=False  # WebP создадим асинхронно
                    )
                    
                    # Загружаем medium версию обратно (для немедленного использования)
                    if "medium" in processed_files and media_service.s3_client:
                        base_key = request.file_key.rsplit('.', 1)[0]
                        medium_key = f"{base_key}_medium.jpg"
                        media_service.s3_client.upload_file(
                            processed_files["medium"],
                            media_service.bucket,
                            medium_key
                        )
                        image_processing.medium_url = f"{media_service.cdn_url}/{medium_key}"
                        # Обновляем result URL на medium версию для немедленного использования
                        result["url"] = image_processing.medium_url
                        db.commit()
                    elif "medium" in processed_files and not media_service.s3_client:
                        # Локальная разработка - копируем файл
                        base_key = request.file_key.rsplit('.', 1)[0]
                        medium_key = f"{base_key}_medium.jpg"
                        medium_path_full = os.path.join(os.getcwd(), medium_key)
                        os.makedirs(os.path.dirname(medium_path_full), exist_ok=True)
                        shutil.copy2(processed_files["medium"], medium_path_full)
                        _pub = settings.API_PUBLIC_BASE_URL.rstrip("/")
                        image_processing.medium_url = f"{_pub}/api/v1/uploads/file/{medium_key}"
                        result["url"] = image_processing.medium_url
                        db.commit()
                    
                finally:
                    # Удаляем временную директорию
                    try:
                        shutil.rmtree(temp_dir)
                    except Exception as e:
                        logger.warning(f"Failed to cleanup temp directory {temp_dir}: {e}")
                        
            except Exception as e:
                # Если синхронная обработка не удалась, продолжаем с оригинальным URL
                # Полная обработка все равно будет выполнена асинхронно
                logger.warning(f"Sync image processing failed, using original: {e}")
        
        return result
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to complete upload: {str(e)}"
        )


@router.get("/status/{upload_id}")
async def get_upload_status(
    upload_id: str,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """
    Получить статус обработки загрузки
    
    Полезно для видео и изображений, которые обрабатываются асинхронно.
    """
    from app.models.video_processing import VideoProcessing
    from app.models.image_processing import ImageProcessing
    
    try:
        # Сначала проверяем видео
        video_processing = db.query(VideoProcessing).filter(
            VideoProcessing.upload_id == upload_id
        ).first()
        
        if video_processing:
            return {
                "status": video_processing.status,
                "progress": video_processing.progress,
                "url": video_processing.mp4_720p_url or video_processing.mp4_1080p_url,
                "mp4_1080p_url": video_processing.mp4_1080p_url,
                "mp4_720p_url": video_processing.mp4_720p_url,
                "mp4_480p_url": video_processing.mp4_480p_url,
                "hls_url": video_processing.hls_url,
                "thumbnail_url": video_processing.thumbnail_url,
                "error_message": video_processing.error_message
            }
        
        # Проверяем изображение
        image_processing = db.query(ImageProcessing).filter(
            ImageProcessing.upload_id == upload_id
        ).first()
        
        if image_processing:
            return {
                "status": image_processing.status,
                "progress": image_processing.progress,
                "url": image_processing.large_url,  # Основной URL
                "large_url": image_processing.large_url,
                "medium_url": image_processing.medium_url,
                "thumbnail_url": image_processing.thumbnail_url,
                "large_webp_url": image_processing.large_webp_url,
                "medium_webp_url": image_processing.medium_webp_url,
                "thumbnail_webp_url": image_processing.thumbnail_webp_url,
                "error_message": image_processing.error_message
            }
        
        # Если нет в БД, используем MediaService (для обратной совместимости)
        media_service = MediaService()
        result = media_service.get_upload_status(upload_id)
        return result
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get upload status: {str(e)}"
        )


@router.put("/mock/{upload_id}")
async def mock_upload(
    upload_id: str,
    request: Request,
    current_user: User = Depends(get_current_user_required)
):
    """
    Mock эндпоинт для локальной загрузки файлов (когда S3 не настроен)
    
    В реальном окружении файлы загружаются напрямую в S3 по presigned URL.
    Этот эндпоинт используется только для разработки без S3.
    """
    import os
    from botocore.exceptions import ClientError
    
    _enforce_upload_rate_limit(current_user.id, "mock_put", 30)
    try:
        # Получаем file_key (память + Redis, чтобы пережить перезапуск API)
        file_key = _lookup_mock_file_key(upload_id)
        if not file_key:
            logger.warning(
                "mock PUT: unknown upload_id=%s (возможен перезапуск сервера без Redis — снова вызовите /init)",
                upload_id,
            )
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Upload ID not found. Call /uploads/init again (server may have restarted).",
            )
        
        # Получаем тело запроса как байты
        file_data = await request.body()
        if not file_data:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Empty upload body",
            )

        media_service = MediaService()
        content_type = (
            request.headers.get("content-type") or "application/octet-stream"
        )

        if media_service.s3_client:
            try:
                media_service.s3_client.put_object(
                    Bucket=media_service.bucket,
                    Key=file_key,
                    Body=file_data,
                    ContentType=content_type,
                )
            except ClientError as e:
                logger.exception("API upload to S3 failed for %s", file_key)
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail=f"S3 upload failed: {e}",
                ) from e
            url = f"{media_service.cdn_url}/{file_key}"
            return {"ok": True, "url": url, "file_key": file_key}
        
        # Локальная разработка без S3
        uploads_dir = os.path.join(os.getcwd(), "uploads")
        os.makedirs(uploads_dir, exist_ok=True)
        
        # Создаем полный путь к файлу на основе file_key
        # file_key имеет формат: uploads/user_2/2025/12/10/uuid.jpg
        # Сохраняем как: uploads/user_2/2025/12/10/uuid.jpg
        file_path = os.path.join(os.getcwd(), file_key)
        
        # Создаем директории, если их нет
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        
        # Сохраняем файл
        with open(file_path, "wb") as f:
            f.write(file_data)
        
        # Возвращаем успешный ответ с локальным URL
        # URL будет доступен через эндпоинт /api/v1/uploads/file/{file_key}
        _pub = settings.API_PUBLIC_BASE_URL.rstrip("/")
        return {
            "status": "uploaded",
            "file_key": file_key,
            "url": f"{_pub}/api/v1/uploads/file/{file_key}"
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to upload file: {str(e)}"
        )


@router.get("/file/{file_path:path}")
async def get_uploaded_file(file_path: str, request: Request):
    """
    Получить загруженный файл.

    Локально — с диска; в production при отсутствии на диске — из S3.
    Поддержка HTTP Range (206) обязательна для AVPlayer / audioplayers на iOS.
    """
    import os

    from botocore.exceptions import ClientError

    from app.core.ranged_file import (
        content_type_for_upload_path,
        ranged_file_response,
        ranged_s3_object_response,
    )

    if ".." in file_path:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid file path",
        )

    if not file_path.startswith("uploads/"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid file path",
        )

    content_type = content_type_for_upload_path(file_path)
    file_path_full = os.path.join(os.getcwd(), file_path)
    cwd = os.getcwd()
    if (
        os.path.exists(file_path_full)
        and os.path.abspath(file_path_full).startswith(os.path.abspath(cwd))
    ):
        return ranged_file_response(
            file_path_full,
            request,
            media_type=content_type,
        )

    media_service = MediaService()
    if media_service.s3_client:
        try:
            return ranged_s3_object_response(
                media_service.s3_client,
                media_service.bucket,
                file_path,
                request,
                media_type=content_type,
            )
        except ClientError as e:
            code = e.response.get("Error", {}).get("Code", "")
            if code in ("404", "NoSuchKey", "NotFound"):
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="File not found",
                ) from e
            logger.exception("S3 file read failed for %s", file_path)
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Failed to read file from storage",
            ) from e

    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="File not found",
    )
