"""
Сервис для транскодинга видео (FFmpeg)
"""
import os
import subprocess
import logging
import tempfile
from pathlib import Path
from typing import Dict, Optional, Tuple
from app.core.config import settings
from app.services.media_service import MediaService

logger = logging.getLogger(__name__)


class VideoTranscodingService:
    """Сервис для транскодинга видео с использованием FFmpeg"""
    
    def __init__(self):
        self.media_service = MediaService()
        self.ffmpeg_path = self._find_ffmpeg()
        
        if not self.ffmpeg_path:
            logger.warning("FFmpeg not found. Video transcoding will not work.")
    
    def _find_ffmpeg(self) -> Optional[str]:
        """Найти путь к FFmpeg"""
        # Проверяем переменную окружения
        ffmpeg_path = os.getenv("FFMPEG_PATH")
        if ffmpeg_path and os.path.exists(ffmpeg_path):
            return ffmpeg_path
        
        # Пытаемся найти в PATH
        try:
            result = subprocess.run(
                ["ffmpeg", "-version"],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                return "ffmpeg"
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass
        
        return None
    
    def transcode_video(
        self,
        input_file_path: str,
        output_dir: str,
        upload_id: str
    ) -> Dict[str, str]:
        """
        Транскодировать видео в несколько форматов
        
        Args:
            input_file_path: путь к исходному видео файлу
            output_dir: директория для сохранения результатов
            upload_id: ID загрузки (для именования файлов)
            
        Returns:
            {
                "mp4_720p": "path/to/file_720p.mp4",
                "mp4_480p": "path/to/file_480p.mp4",
                "hls": "path/to/file.m3u8",
                "thumbnail": "path/to/thumbnail.jpg"
            }
        """
        if not self.ffmpeg_path:
            raise RuntimeError("FFmpeg is not available")
        
        output_dir_path = Path(output_dir)
        output_dir_path.mkdir(parents=True, exist_ok=True)
        
        results = {}
        
        try:
            # 1. MP4 720p
            mp4_720p_path = output_dir_path / f"{upload_id}_720p.mp4"
            self._transcode_to_mp4(
                input_file_path,
                str(mp4_720p_path),
                width=1280,
                height=720,
                bitrate="2500k"
            )
            results["mp4_720p"] = str(mp4_720p_path)
            
            # 2. MP4 480p
            mp4_480p_path = output_dir_path / f"{upload_id}_480p.mp4"
            self._transcode_to_mp4(
                input_file_path,
                str(mp4_480p_path),
                width=854,
                height=480,
                bitrate="1000k"
            )
            results["mp4_480p"] = str(mp4_480p_path)
            
            # 3. HLS (для адаптивного стриминга)
            hls_dir = output_dir_path / f"{upload_id}_hls"
            hls_dir.mkdir(exist_ok=True)
            hls_playlist = hls_dir / "playlist.m3u8"
            self._transcode_to_hls(
                input_file_path,
                str(hls_playlist),
                hls_dir
            )
            results["hls"] = str(hls_playlist)
            
            # 4. Thumbnail (кадр на 1 секунде)
            thumbnail_path = output_dir_path / f"{upload_id}_thumb.jpg"
            self._extract_thumbnail(
                input_file_path,
                str(thumbnail_path),
                timestamp=1.0
            )
            results["thumbnail"] = str(thumbnail_path)
            
            return results
            
        except Exception as e:
            logger.error(f"Error transcoding video {upload_id}: {e}")
            # Удаляем частично созданные файлы
            for file_path in results.values():
                try:
                    if os.path.exists(file_path):
                        if os.path.isdir(file_path):
                            import shutil
                            shutil.rmtree(file_path)
                        else:
                            os.remove(file_path)
                except Exception:
                    pass
            raise
    
    def _transcode_to_mp4(
        self,
        input_path: str,
        output_path: str,
        width: int,
        height: int,
        bitrate: str
    ):
        """Транскодировать в MP4 с заданными параметрами"""
        cmd = [
            self.ffmpeg_path,
            "-i", input_path,
            "-vf", f"scale={width}:{height}:force_original_aspect_ratio=decrease,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2",
            "-c:v", "libx264",
            "-preset", "medium",
            "-crf", "23",
            "-b:v", bitrate,
            "-c:a", "aac",
            "-b:a", "128k",
            "-movflags", "+faststart",  # Для быстрого старта воспроизведения
            "-y",  # Перезаписать если существует
            output_path
        ]
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=600  # 10 минут максимум
        )
        
        if result.returncode != 0:
            raise RuntimeError(f"FFmpeg error: {result.stderr}")
    
    def _transcode_to_hls(
        self,
        input_path: str,
        output_playlist: str,
        output_dir: Path
    ):
        """Транскодировать в HLS формат"""
        # Создаем несколько вариантов качества для адаптивного стриминга
        qualities = [
            {"name": "720p", "width": 1280, "height": 720, "bitrate": "2500k"},
            {"name": "480p", "width": 854, "height": 480, "bitrate": "1000k"},
            {"name": "360p", "width": 640, "height": 360, "bitrate": "500k"},
        ]
        
        segment_pattern = output_dir / "segment_%03d.ts"
        playlist_pattern = output_dir / "playlist_%s.m3u8"
        
        # Генерируем сегменты для каждого качества
        for quality in qualities:
            playlist_path = str(playlist_pattern).replace("%s", quality["name"])
            segment_path = str(segment_pattern).replace("%03d", f"{quality['name']}_%03d")
            
            cmd = [
                self.ffmpeg_path,
                "-i", input_path,
                "-vf", f"scale={quality['width']}:{quality['height']}:force_original_aspect_ratio=decrease",
                "-c:v", "libx264",
                "-preset", "medium",
                "-crf", "23",
                "-b:v", quality["bitrate"],
                "-c:a", "aac",
                "-b:a", "128k",
                "-f", "hls",
                "-hls_time", "10",  # 10 секунд на сегмент
                "-hls_list_size", "0",  # Все сегменты в плейлисте
                "-hls_segment_filename", segment_path,
                "-y",
                playlist_path
            ]
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=600
            )
            
            if result.returncode != 0:
                raise RuntimeError(f"FFmpeg HLS error: {result.stderr}")
        
        # Создаем мастер-плейлист
        master_playlist_content = "#EXTM3U\n#EXT-X-VERSION:3\n"
        for quality in qualities:
            playlist_name = f"playlist_{quality['name']}.m3u8"
            master_playlist_content += f"#EXT-X-STREAM-INF:BANDWIDTH={quality['bitrate'].replace('k', '000')},RESOLUTION={quality['width']}x{quality['height']}\n"
            master_playlist_content += f"{playlist_name}\n"
        
        with open(output_playlist, "w") as f:
            f.write(master_playlist_content)
    
    def _extract_thumbnail(
        self,
        input_path: str,
        output_path: str,
        timestamp: float = 1.0
    ):
        """Извлечь кадр из видео для превью"""
        cmd = [
            self.ffmpeg_path,
            "-i", input_path,
            "-ss", str(timestamp),
            "-vframes", "1",
            "-vf", "scale=640:-1",  # Ширина 640, высота автоматически
            "-q:v", "2",  # Качество JPEG (2 = высокое)
            "-y",
            output_path
        ]
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if result.returncode != 0:
            raise RuntimeError(f"FFmpeg thumbnail error: {result.stderr}")
    
    def get_video_info(self, video_path: str) -> Dict[str, any]:
        """Получить информацию о видео (длительность, разрешение)"""
        if not self.ffmpeg_path:
            return {}
        
        cmd = [
            self.ffmpeg_path,
            "-i", video_path,
            "-hide_banner"
        ]
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        # Парсим вывод FFmpeg для получения информации
        # Это упрощенная версия, в продакшене лучше использовать ffprobe
        info = {}
        
        # Ищем длительность
        for line in result.stderr.split("\n"):
            if "Duration:" in line:
                duration_str = line.split("Duration:")[1].split(",")[0].strip()
                # Парсим HH:MM:SS.mmm
                parts = duration_str.split(":")
                if len(parts) == 3:
                    hours = float(parts[0])
                    minutes = float(parts[1])
                    seconds = float(parts[2])
                    info["duration"] = hours * 3600 + minutes * 60 + seconds
            
            # Ищем разрешение
            if "Video:" in line and "x" in line:
                # Ищем паттерн вида "1920x1080"
                import re
                match = re.search(r"(\d+)x(\d+)", line)
                if match:
                    info["width"] = int(match.group(1))
                    info["height"] = int(match.group(2))
        
        return info

