"""
API endpoints для загрузки медиа
"""
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
    file_type: str  # image | video
    content_type: str  # image/jpeg, video/mp4, etc.
    file_size: int  # размер в байтах


class CompleteUploadRequest(BaseModel):
    upload_id: str
    file_key: str
    file_type: str  # image | video


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
    try:
        media_service = MediaService()
        result = media_service.generate_presigned_url(
            file_type=request.file_type,
            content_type=request.content_type,
            file_size=request.file_size,
            user_id=current_user.id
        )
        # API-загрузка (mock): запоминаем upload_id → file_key
        if result.get("upload_via") == "api" or not media_service.s3_client:
            _remember_mock_upload(result["upload_id"], result["file_key"])
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
    
    try:
        media_service = MediaService()
        result = media_service.complete_upload(
            upload_id=request.upload_id,
            file_key=request.file_key,
            file_type=request.file_type,
            user_id=current_user.id
        )
        
        # Если это видео, добавляем в очередь обработки
        if request.file_type == "video":
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
                "url": video_processing.mp4_720p_url,  # Основной URL
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
        
        # Сохраняем файл локально по пути, соответствующему file_key
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
async def get_uploaded_file(file_path: str):
    """
    Получить загруженный файл (для локальной разработки)
    
    В production файлы должны раздаваться через CDN или веб-сервер (nginx).
    """
    import os
    from fastapi.responses import FileResponse
    
    # Безопасность: проверяем, что путь не содержит опасных символов
    if '..' in file_path:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid file path"
        )
    
    # file_path имеет формат: uploads/user_2/2025/12/10/uuid.jpg
    # Создаем полный путь относительно корня проекта
    file_path_full = os.path.join(os.getcwd(), file_path)
    
    # Проверяем, что файл существует и находится в корне проекта
    if not os.path.exists(file_path_full) or not file_path_full.startswith(os.getcwd()):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="File not found"
        )
    
    # Определяем content type по расширению
    content_type = "application/octet-stream"
    if file_path.endswith('.jpg') or file_path.endswith('.jpeg'):
        content_type = "image/jpeg"
    elif file_path.endswith('.png'):
        content_type = "image/png"
    elif file_path.endswith('.gif'):
        content_type = "image/gif"
    elif file_path.endswith('.webp'):
        content_type = "image/webp"
    elif file_path.endswith('.mp4'):
        content_type = "video/mp4"
    
    return FileResponse(
        file_path_full,
        media_type=content_type,
        headers={
            "Cache-Control": "public, max-age=31536000",  # Кэшируем на год
        }
    )
