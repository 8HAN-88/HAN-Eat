"""
Worker для обработки видео из очереди
"""
import os
import sys
import json
import logging
import tempfile
import shutil
from pathlib import Path
from typing import Optional

# Добавляем путь к app
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(__file__))))

from sqlalchemy.orm import Session
from app.core.database import SessionLocal
from app.core.redis_client import redis_client
from app.models.video_processing import VideoProcessing
from app.services.video_transcoding_service import VideoTranscodingService
from app.services.video_queue_service import VideoQueueService
from app.services.media_service import MediaService
from datetime import datetime

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class VideoWorker:
    """Worker для обработки видео"""
    
    def __init__(self):
        self.transcoding_service = VideoTranscodingService()
        self.media_service = MediaService()
        self.db: Session = SessionLocal()
    
    def process_queue(self, max_tasks: Optional[int] = None):
        """
        Обработать задачи из очереди
        
        Args:
            max_tasks: максимальное количество задач для обработки (None = бесконечно)
        """
        tasks_processed = 0
        
        logger.info("Video worker started. Waiting for tasks...")
        
        while True:
            if max_tasks and tasks_processed >= max_tasks:
                logger.info(f"Processed {tasks_processed} tasks. Stopping.")
                break
            
            # Получаем задачу из очереди
            task_data = VideoQueueService.dequeue_video_processing()
            
            if not task_data:
                # Нет задач, ждем немного
                import time
                time.sleep(5)
                continue
            
            try:
                self._process_video_task(task_data)
                tasks_processed += 1
            except Exception as e:
                logger.error(f"Error processing video task {task_data.get('upload_id')}: {e}", exc_info=True)
                self._mark_task_failed(task_data.get('upload_id'), str(e))
    
    def _process_video_task(self, task_data: dict):
        """Обработать одну задачу видео"""
        upload_id = task_data.get("upload_id")
        file_key = task_data.get("file_key")
        processing_id = task_data.get("processing_id")
        
        logger.info(f"Processing video: upload_id={upload_id}, file_key={file_key}")
        
        # Обновляем статус на processing
        video_processing = self.db.query(VideoProcessing).filter(
            VideoProcessing.id == processing_id
        ).first()
        
        if not video_processing:
            logger.error(f"VideoProcessing record not found: {processing_id}")
            return
        
        video_processing.status = "processing"
        video_processing.progress = 0.0
        self.db.commit()
        
        VideoQueueService.update_processing_status(upload_id, "processing", 0.0)
        
        # Создаем временную директорию для обработки
        temp_dir = tempfile.mkdtemp(prefix=f"video_{upload_id}_")
        
        try:
            # 1. Скачиваем файл из S3
            logger.info(f"Downloading file from S3: {file_key}")
            video_processing.progress = 10.0
            self.db.commit()
            VideoQueueService.update_processing_status(upload_id, "processing", 10.0)
            
            input_file_path = os.path.join(temp_dir, "input_video.mp4")
            self._download_from_s3(file_key, input_file_path)
            
            # 2. Получаем информацию о видео
            logger.info("Getting video info")
            video_info = self.transcoding_service.get_video_info(input_file_path)
            if video_info:
                video_processing.original_duration = video_info.get("duration")
                video_processing.original_width = video_info.get("width")
                video_processing.original_height = video_info.get("height")
            
            # 3. Транскодируем видео
            logger.info("Transcoding video")
            video_processing.progress = 20.0
            self.db.commit()
            VideoQueueService.update_processing_status(upload_id, "processing", 20.0)
            
            output_dir = os.path.join(temp_dir, "output")
            os.makedirs(output_dir, exist_ok=True)
            
            transcoded_files = self.transcoding_service.transcode_video(
                input_file_path=input_file_path,
                output_dir=output_dir,
                upload_id=upload_id
            )
            
            # 4. Загружаем результаты обратно в S3
            logger.info("Uploading transcoded files to S3")
            video_processing.progress = 80.0
            self.db.commit()
            VideoQueueService.update_processing_status(upload_id, "processing", 80.0)
            
            # Загружаем MP4 720p
            if "mp4_720p" in transcoded_files:
                mp4_720p_key = f"{file_key.rsplit('.', 1)[0]}_720p.mp4"
                self._upload_to_s3(transcoded_files["mp4_720p"], mp4_720p_key)
                video_processing.mp4_720p_url = f"{self.media_service.cdn_url}/{mp4_720p_key}"
            
            # Загружаем MP4 480p
            if "mp4_480p" in transcoded_files:
                mp4_480p_key = f"{file_key.rsplit('.', 1)[0]}_480p.mp4"
                self._upload_to_s3(transcoded_files["mp4_480p"], mp4_480p_key)
                video_processing.mp4_480p_url = f"{self.media_service.cdn_url}/{mp4_480p_key}"
            
            # Загружаем HLS
            if "hls" in transcoded_files:
                hls_dir_key = f"{file_key.rsplit('.', 1)[0]}_hls/"
                self._upload_hls_directory(transcoded_files["hls"], hls_dir_key)
                video_processing.hls_url = f"{self.media_service.cdn_url}/{hls_dir_key}playlist.m3u8"
            
            # Загружаем thumbnail
            if "thumbnail" in transcoded_files:
                thumbnail_key = f"{file_key.rsplit('.', 1)[0]}_thumb.jpg"
                self._upload_to_s3(transcoded_files["thumbnail"], thumbnail_key)
                video_processing.thumbnail_url = f"{self.media_service.cdn_url}/{thumbnail_key}"
            
            # 5. Обновляем статус на completed
            video_processing.status = "completed"
            video_processing.progress = 100.0
            video_processing.completed_at = datetime.utcnow()
            self.db.commit()
            
            VideoQueueService.update_processing_status(upload_id, "completed", 100.0)
            
            logger.info(f"Video processing completed: {upload_id}")
            
        except Exception as e:
            logger.error(f"Error processing video {upload_id}: {e}", exc_info=True)
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
    
    def _upload_hls_directory(self, playlist_path: str, s3_dir_key: str):
        """Загрузить HLS директорию в S3"""
        if not self.media_service.s3_client:
            return  # Mock
        
        playlist_dir = Path(playlist_path).parent
        
        # Загружаем все файлы из директории
        for file_path in playlist_dir.rglob("*"):
            if file_path.is_file():
                relative_path = file_path.relative_to(playlist_dir)
                s3_key = f"{s3_dir_key}{relative_path.as_posix()}"
                self._upload_to_s3(str(file_path), s3_key)
    
    def _mark_task_failed(self, upload_id: str, error_message: str):
        """Пометить задачу как failed"""
        video_processing = self.db.query(VideoProcessing).filter(
            VideoProcessing.upload_id == upload_id
        ).first()
        
        if video_processing:
            video_processing.status = "failed"
            video_processing.error_message = error_message
            self.db.commit()
        
        VideoQueueService.update_processing_status(
            upload_id,
            "failed",
            error_message=error_message
        )


def main():
    """Точка входа для worker"""
    worker = VideoWorker()
    
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

