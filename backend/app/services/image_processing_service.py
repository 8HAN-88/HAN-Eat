"""
Сервис для обработки и оптимизации изображений
"""
import os
import logging
from pathlib import Path
from typing import Dict, Optional, Tuple
from PIL import Image, ImageOps
import io

logger = logging.getLogger(__name__)


class ImageProcessingService:
    """Сервис для обработки и оптимизации изображений"""
    
    # Размеры для разных вариантов
    THUMBNAIL_SIZE = (320, 320)  # Квадратное превью
    MEDIUM_SIZE = (800, 800)  # Средний размер
    LARGE_SIZE = (1920, 1920)  # Большой размер (максимум)
    
    JPEG_QUALITY = 85  # Качество JPEG (0-100)
    WEBP_QUALITY = 85  # Качество WebP (0-100)
    
    def __init__(self):
        self.supported_formats = ['JPEG', 'PNG', 'WEBP']
    
    def process_image(
        self,
        input_file_path: str,
        output_dir: str,
        upload_id: str,
        generate_webp: bool = True
    ) -> Dict[str, str]:
        """
        Обработать изображение: создать несколько размеров и форматов
        
        Args:
            input_file_path: путь к исходному изображению
            output_dir: директория для сохранения результатов
            upload_id: ID загрузки (для именования файлов)
            generate_webp: создавать ли WebP версии
            
        Returns:
            {
                "original": "path/to/original.jpg",
                "large": "path/to/large.jpg",
                "medium": "path/to/medium.jpg",
                "thumbnail": "path/to/thumbnail.jpg",
                "large_webp": "path/to/large.webp" (опционально),
                "medium_webp": "path/to/medium.webp" (опционально),
                "thumbnail_webp": "path/to/thumbnail.webp" (опционально)
            }
        """
        output_dir_path = Path(output_dir)
        output_dir_path.mkdir(parents=True, exist_ok=True)
        
        results = {}
        
        try:
            # Открываем исходное изображение
            with Image.open(input_file_path) as img:
                # Конвертируем в RGB если нужно (для JPEG)
                if img.mode in ('RGBA', 'LA', 'P'):
                    # Создаем белый фон для прозрачных изображений
                    rgb_img = Image.new('RGB', img.size, (255, 255, 255))
                    if img.mode == 'P':
                        img = img.convert('RGBA')
                    rgb_img.paste(img, mask=img.split()[-1] if img.mode in ('RGBA', 'LA') else None)
                    img = rgb_img
                elif img.mode != 'RGB':
                    img = img.convert('RGB')
                
                # Автоматически поворачиваем по EXIF
                img = ImageOps.exif_transpose(img)
                
                original_width, original_height = img.size
                
                # 1. Large (максимальный размер, но не больше оригинала)
                large_size = self._calculate_size(
                    original_width,
                    original_height,
                    self.LARGE_SIZE[0],
                    self.LARGE_SIZE[1]
                )
                large_path = output_dir_path / f"{upload_id}_large.jpg"
                self._resize_and_save(
                    img,
                    large_size,
                    str(large_path),
                    quality=self.JPEG_QUALITY
                )
                results["large"] = str(large_path)
                
                # 2. Medium
                medium_size = self._calculate_size(
                    original_width,
                    original_height,
                    self.MEDIUM_SIZE[0],
                    self.MEDIUM_SIZE[1]
                )
                medium_path = output_dir_path / f"{upload_id}_medium.jpg"
                self._resize_and_save(
                    img,
                    medium_size,
                    str(medium_path),
                    quality=self.JPEG_QUALITY
                )
                results["medium"] = str(medium_path)
                
                # 3. Thumbnail (квадратное)
                thumbnail_path = output_dir_path / f"{upload_id}_thumbnail.jpg"
                self._create_thumbnail(
                    img,
                    str(thumbnail_path),
                    size=self.THUMBNAIL_SIZE[0]
                )
                results["thumbnail"] = str(thumbnail_path)
                
                # 4. WebP версии (если нужно)
                if generate_webp:
                    # Large WebP
                    large_webp_path = output_dir_path / f"{upload_id}_large.webp"
                    self._resize_and_save_webp(
                        img,
                        large_size,
                        str(large_webp_path),
                        quality=self.WEBP_QUALITY
                    )
                    results["large_webp"] = str(large_webp_path)
                    
                    # Medium WebP
                    medium_webp_path = output_dir_path / f"{upload_id}_medium.webp"
                    self._resize_and_save_webp(
                        img,
                        medium_size,
                        str(medium_webp_path),
                        quality=self.WEBP_QUALITY
                    )
                    results["medium_webp"] = str(medium_webp_path)
                    
                    # Thumbnail WebP
                    thumbnail_webp_path = output_dir_path / f"{upload_id}_thumbnail.webp"
                    thumbnail_img = self._create_thumbnail_image(img, self.THUMBNAIL_SIZE[0])
                    thumbnail_img.save(
                        str(thumbnail_webp_path),
                        'WEBP',
                        quality=self.WEBP_QUALITY,
                        method=6  # Максимальное сжатие
                    )
                    results["thumbnail_webp"] = str(thumbnail_webp_path)
            
            return results
            
        except Exception as e:
            logger.error(f"Error processing image {upload_id}: {e}", exc_info=True)
            # Удаляем частично созданные файлы
            for file_path in results.values():
                try:
                    if os.path.exists(file_path):
                        os.remove(file_path)
                except Exception:
                    pass
            raise
    
    def _calculate_size(
        self,
        original_width: int,
        original_height: int,
        max_width: int,
        max_height: int
    ) -> Tuple[int, int]:
        """
        Вычислить размер с сохранением пропорций
        
        Args:
            original_width: исходная ширина
            original_height: исходная высота
            max_width: максимальная ширина
            max_height: максимальная высота
            
        Returns:
            (width, height) - новые размеры
        """
        # Если изображение меньше максимального размера, оставляем как есть
        if original_width <= max_width and original_height <= max_height:
            return (original_width, original_height)
        
        # Вычисляем коэффициент масштабирования
        width_ratio = max_width / original_width
        height_ratio = max_height / original_height
        ratio = min(width_ratio, height_ratio)
        
        new_width = int(original_width * ratio)
        new_height = int(original_height * ratio)
        
        return (new_width, new_height)
    
    def _resize_and_save(
        self,
        img: Image.Image,
        size: Tuple[int, int],
        output_path: str,
        quality: Optional[int] = None
    ):
        """Изменить размер и сохранить как JPEG"""
        if quality is None:
            quality = self.JPEG_QUALITY
        resized = img.resize(size, Image.Resampling.LANCZOS)
        resized.save(
            output_path,
            'JPEG',
            quality=quality,
            optimize=True,
            progressive=True  # Прогрессивный JPEG для лучшей загрузки
        )
    
    def _resize_and_save_webp(
        self,
        img: Image.Image,
        size: Tuple[int, int],
        output_path: str,
        quality: Optional[int] = None
    ):
        """Изменить размер и сохранить как WebP"""
        if quality is None:
            quality = self.WEBP_QUALITY
        resized = img.resize(size, Image.Resampling.LANCZOS)
        resized.save(
            output_path,
            'WEBP',
            quality=quality,
            method=6  # Максимальное сжатие
        )
    
    def _create_thumbnail(
        self,
        img: Image.Image,
        output_path: str,
        size: int = THUMBNAIL_SIZE[0]
    ):
        """Создать квадратное превью"""
        thumbnail_img = self._create_thumbnail_image(img, size)
        thumbnail_img.save(
            output_path,
            'JPEG',
            quality=self.JPEG_QUALITY,
            optimize=True
        )
    
    def _create_thumbnail_image(
        self,
        img: Image.Image,
        size: int
    ) -> Image.Image:
        """Создать квадратное изображение для превью"""
        # Используем thumbnail для сохранения пропорций
        thumbnail = img.copy()
        thumbnail.thumbnail((size, size), Image.Resampling.LANCZOS)
        
        # Создаем квадратное изображение с белым фоном
        square_img = Image.new('RGB', (size, size), (255, 255, 255))
        
        # Центрируем thumbnail
        x_offset = (size - thumbnail.width) // 2
        y_offset = (size - thumbnail.height) // 2
        square_img.paste(thumbnail, (x_offset, y_offset))
        
        return square_img
    
    def get_image_info(self, image_path: str) -> Dict[str, any]:
        """Получить информацию об изображении"""
        try:
            with Image.open(image_path) as img:
                return {
                    "width": img.width,
                    "height": img.height,
                    "format": img.format,
                    "mode": img.mode,
                    "size_bytes": os.path.getsize(image_path)
                }
        except Exception as e:
            logger.error(f"Error getting image info: {e}")
            return {}

