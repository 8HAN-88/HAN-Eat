"""
Worker для обработки изображений из очереди
"""
import os
import sys
import json
import logging
import tempfile
import shutil
from pathlib import Path
from typing import Optional
from datetime import datetime

# Добавляем путь к app
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(__file__))))

from sqlalchemy.orm import Session
from app.core.database import SessionLocal
from app.core.redis_client import redis_client
from app.models.image_processing import ImageProcessing
from app.services.image_processing_service import ImageProcessingService
from app.services.image_queue_service import ImageQueueService
from app.services.media_service import MediaService

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class ImageWorker:
    """Worker для обработки изображений"""
    
    def __init__(self):
        self.processing_service = ImageProcessingService()
        self.media_service = MediaService()
        self.db: Session = SessionLocal()
    
    def process_queue(self, max_tasks: Optional[int] = None):
        """
        Обработать задачи из очереди
        
        Args:
            max_tasks: максимальное количество задач для обработки (None = бесконечно)
        """
        tasks_processed = 0
        
        logger.info("Image worker started. Waiting for tasks...")
        
        while True:
            if max_tasks and tasks_processed >= max_tasks:
                logger.info(f"Processed {tasks_processed} tasks. Stopping.")
                break
            
            # Получаем задачу из очереди
            task_data = ImageQueueService.dequeue_image_processing()
            
            if not task_data:
                # Нет задач, ждем немного
                import time
                time.sleep(2)  # Для изображений можно ждать меньше
                continue
            
            try:
                self._process_image_task(task_data)
                tasks_processed += 1
            except Exception as e:
                logger.error(f"Error processing image task {task_data.get('upload_id')}: {e}", exc_info=True)
                self._mark_task_failed(task_data.get('upload_id'), str(e))
    
    def _process_image_task(self, task_data: dict):
        """Обработать одну задачу изображения"""
        upload_id = task_data.get("upload_id")
        file_key = task_data.get("file_key")
        processing_id = task_data.get("processing_id")
        
        logger.info(f"Processing image: upload_id={upload_id}, file_key={file_key}")
        
        # Обновляем статус на processing
        image_processing = self.db.query(ImageProcessing).filter(
            ImageProcessing.id == processing_id
        ).first()
        
        if not image_processing:
            logger.error(f"ImageProcessing record not found: {processing_id}")
            return
        
        image_processing.status = "processing"
        image_processing.progress = 0.0
        self.db.commit()
        
        ImageQueueService.update_processing_status(upload_id, "processing", 0.0)
        
        # Создаем временную директорию для обработки
        temp_dir = tempfile.mkdtemp(prefix=f"image_{upload_id}_")
        
        try:
            # 1. Скачиваем файл из S3
            logger.info(f"Downloading file from S3: {file_key}")
            image_processing.progress = 10.0
            self.db.commit()
            ImageQueueService.update_processing_status(upload_id, "processing", 10.0)
            
            input_file_path = os.path.join(temp_dir, "input_image.jpg")
            self._download_from_s3(file_key, input_file_path)
            
            # 2. Получаем информацию об изображении
            logger.info("Getting image info")
            image_info = self.processing_service.get_image_info(input_file_path)
            if image_info:
                image_processing.original_width = image_info.get("width")
                image_processing.original_height = image_info.get("height")
                image_processing.original_size_bytes = image_info.get("size_bytes")
            
            # 3. Обрабатываем изображение
            logger.info("Processing image")
            image_processing.progress = 30.0
            self.db.commit()
            ImageQueueService.update_processing_status(upload_id, "processing", 30.0)
            
            output_dir = os.path.join(temp_dir, "output")
            os.makedirs(output_dir, exist_ok=True)
            
            processed_files = self.processing_service.process_image(
                input_file_path=input_file_path,
                output_dir=output_dir,
                upload_id=upload_id,
                generate_webp=True
            )
            
            # 4. Загружаем результаты обратно в S3
            logger.info("Uploading processed files to S3")
            image_processing.progress = 70.0
            self.db.commit()
            ImageQueueService.update_processing_status(upload_id, "processing", 70.0)
            
            # Загружаем все варианты
            base_key = file_key.rsplit('.', 1)[0]
            
            if "large" in processed_files:
                large_key = f"{base_key}_large.jpg"
                self._upload_to_s3(processed_files["large"], large_key)
                image_processing.large_url = f"{self.media_service.cdn_url}/{large_key}"
            
            if "medium" in processed_files:
                medium_key = f"{base_key}_medium.jpg"
                self._upload_to_s3(processed_files["medium"], medium_key)
                image_processing.medium_url = f"{self.media_service.cdn_url}/{medium_key}"
            
            if "thumbnail" in processed_files:
                thumbnail_key = f"{base_key}_thumbnail.jpg"
                self._upload_to_s3(processed_files["thumbnail"], thumbnail_key)
                image_processing.thumbnail_url = f"{self.media_service.cdn_url}/{thumbnail_key}"
            
            if "large_webp" in processed_files:
                large_webp_key = f"{base_key}_large.webp"
                self._upload_to_s3(processed_files["large_webp"], large_webp_key)
                image_processing.large_webp_url = f"{self.media_service.cdn_url}/{large_webp_key}"
            
            if "medium_webp" in processed_files:
                medium_webp_key = f"{base_key}_medium.webp"
                self._upload_to_s3(processed_files["medium_webp"], medium_webp_key)
                image_processing.medium_webp_url = f"{self.media_service.cdn_url}/{medium_webp_key}"
            
            if "thumbnail_webp" in processed_files:
                thumbnail_webp_key = f"{base_key}_thumbnail.webp"
                self._upload_to_s3(processed_files["thumbnail_webp"], thumbnail_webp_key)
                image_processing.thumbnail_webp_url = f"{self.media_service.cdn_url}/{thumbnail_webp_key}"
            
            # 5. Обновляем статус на completed
            image_processing.status = "completed"
            image_processing.progress = 100.0
            image_processing.completed_at = datetime.utcnow()
            self.db.commit()
            
            ImageQueueService.update_processing_status(upload_id, "completed", 100.0)
            
            logger.info(f"Image processing completed: {upload_id}")
            
        except Exception as e:
            logger.error(f"Error processing image {upload_id}: {e}", exc_info=True)
            self._mark_task_failed(upload_id, str(e))
        finally:
            # Удаляем временную директорию
            try:
                shutil.rmtree(temp_dir)
            except Exception as e:
                logger.warning(f"Failed to cleanup temp directory {temp_dir}: {e}")
    
    def _download_from_s3(self, file_key: str, local_path: str):
        """Скачать файл из S3"""
        if not self.media_service.s3_client:
            # Для локальной разработки создаем пустой файл
            Path(local_path).parent.mkdir(parents=True, exist_ok=True)
            Path(local_path).touch()
            return
        
        self.media_service.s3_client.download_file(
            self.media_service.bucket,
            file_key,
            local_path
        )
    
    def _upload_to_s3(self, local_path: str, s3_key: str):
        """Загрузить файл в S3"""
        if not self.media_service.s3_client:
            return  # Mock для локальной разработки
        
        self.media_service.s3_client.upload_file(
            local_path,
            self.media_service.bucket,
            s3_key
        )
    
    def _mark_task_failed(self, upload_id: str, error_message: str):
        """Пометить задачу как failed"""
        image_processing = self.db.query(ImageProcessing).filter(
            ImageProcessing.upload_id == upload_id
        ).first()
        
        if image_processing:
            image_processing.status = "failed"
            image_processing.error_message = error_message
            self.db.commit()
        
        ImageQueueService.update_processing_status(
            upload_id,
            "failed",
            error_message=error_message
        )


def main():
    """Точка входа для worker"""
    worker = ImageWorker()
    
    try:
        worker.process_queue()
    except KeyboardInterrupt:
        logger.info("Worker stopped by user")
    except Exception as e:
        logger.error(f"Worker crashed: {e}", exc_info=True)
    finally:
        worker.db.close()


if __name__ == "__main__":
    main()

