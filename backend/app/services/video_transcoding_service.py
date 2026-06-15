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

        source_info = self.get_video_info(input_file_path)
        source_height = int(source_info.get("height") or 0)
        source_width = int(source_info.get("width") or 0)
        portrait = source_height > source_width if source_width and source_height else False
        dims_1080, dims_720, dims_480 = self._tier_dimensions(portrait)
        # 1080p только если исходник достаточно крупный (вертикаль 9:16 или горизонталь 16:9).
        if portrait:
            include_1080p = source_width >= 1080 or source_height >= 1920
        else:
            include_1080p = source_height >= 1080 or source_width >= 1920
        
        results = {}
        
        try:
            # 1. MP4 1080p (если исходник позволяет)
            if include_1080p:
                mp4_1080p_path = output_dir_path / f"{upload_id}_1080p.mp4"
                self._transcode_to_mp4(
                    input_file_path,
                    str(mp4_1080p_path),
                    width=dims_1080[0],
                    height=dims_1080[1],
                    bitrate="4500k",
                )
                results["mp4_1080p"] = str(mp4_1080p_path)

            # 2. MP4 720p
            mp4_720p_path = output_dir_path / f"{upload_id}_720p.mp4"
            self._transcode_to_mp4(
                input_file_path,
                str(mp4_720p_path),
                width=dims_720[0],
                height=dims_720[1],
                bitrate="2500k"
            )
            results["mp4_720p"] = str(mp4_720p_path)
            
            # 3. MP4 480p
            mp4_480p_path = output_dir_path / f"{upload_id}_480p.mp4"
            self._transcode_to_mp4(
                input_file_path,
                str(mp4_480p_path),
                width=dims_480[0],
                height=dims_480[1],
                bitrate="1000k"
            )
            results["mp4_480p"] = str(mp4_480p_path)
            
            # 4. HLS (для адаптивного стриминга; не блокирует MP4 при ошибке)
            hls_dir = output_dir_path / f"{upload_id}_hls"
            hls_dir.mkdir(exist_ok=True)
            hls_playlist = hls_dir / "playlist.m3u8"
            try:
                self._transcode_to_hls(
                    input_file_path,
                    str(hls_playlist),
                    hls_dir,
                    include_1080p=include_1080p,
                    portrait=portrait,
                )
                results["hls"] = str(hls_playlist)
            except Exception as hls_err:
                logger.warning(
                    "HLS transcode skipped for %s: %s",
                    upload_id,
                    hls_err,
                )
            
            # 5. Thumbnail (кадр на 1 секунде)
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
    
    def _tier_dimensions(self, portrait: bool) -> Tuple[Tuple[int, int], Tuple[int, int], Tuple[int, int]]:
        """Размеры MP4: вертикаль 9:16 (как Instagram Reels) или горизонталь 16:9."""
        if portrait:
            return (1080, 1920), (720, 1280), (480, 854)
        return (1920, 1080), (1280, 720), (854, 480)

    def _hls_qualities(self, portrait: bool, include_1080p: bool) -> list:
        dims_1080, dims_720, dims_480 = self._tier_dimensions(portrait)
        qualities = []
        if include_1080p:
            qualities.append(
                {
                    "name": "1080p",
                    "width": dims_1080[0],
                    "height": dims_1080[1],
                    "bitrate": "4500k",
                }
            )
        qualities.extend([
            {"name": "720p", "width": dims_720[0], "height": dims_720[1], "bitrate": "2500k"},
            {"name": "480p", "width": dims_480[0], "height": dims_480[1], "bitrate": "1000k"},
        ])
        if portrait:
            qualities.append({"name": "360p", "width": 360, "height": 640, "bitrate": "500k"})
        else:
            qualities.append({"name": "360p", "width": 640, "height": 360, "bitrate": "500k"})
        return qualities

    def _scale_pad_filter(self, width: int, height: int) -> str:
        """Чётные размеры для libx264 (вертикальные рилсы)."""
        return (
            f"scale={width}:{height}:force_original_aspect_ratio=decrease,"
            f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:black,"
            "scale=trunc(iw/2)*2:trunc(ih/2)*2"
        )

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
            "-vf", self._scale_pad_filter(width, height),
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
        output_dir: Path,
        include_1080p: bool = True,
        portrait: bool = False,
    ):
        """Транскодировать в HLS формат"""
        qualities = self._hls_qualities(portrait, include_1080p)
        
        segment_pattern = output_dir / "segment_%03d.ts"
        playlist_pattern = output_dir / "playlist_%s.m3u8"
        
        # Генерируем сегменты для каждого качества
        for quality in qualities:
            playlist_path = str(playlist_pattern).replace("%s", quality["name"])
            segment_path = str(segment_pattern).replace("%03d", f"{quality['name']}_%03d")
            
            cmd = [
                self.ffmpeg_path,
                "-i", input_path,
                "-vf", self._scale_pad_filter(
                    quality["width"], quality["height"]
                ),
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

