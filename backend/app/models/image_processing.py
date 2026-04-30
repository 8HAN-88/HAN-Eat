"""
Модель для отслеживания обработки изображений
"""
from sqlalchemy import Column, Integer, String, Text, DateTime, Float, ForeignKey
from sqlalchemy.sql import func
from app.core.database import Base


class ImageProcessing(Base):
    __tablename__ = "image_processing"
    
    id = Column(Integer, primary_key=True, index=True)
    upload_id = Column(String(100), unique=True, nullable=False, index=True)
    file_key = Column(Text, nullable=False)  # S3 ключ исходного файла
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    
    # Статус обработки
    status = Column(String(20), default="pending", nullable=False, index=True)  # pending | processing | completed | failed
    progress = Column(Float, default=0.0)  # 0.0 - 100.0
    
    # Результаты обработки
    large_url = Column(Text, nullable=True)  # URL для large размера
    medium_url = Column(Text, nullable=True)  # URL для medium размера
    thumbnail_url = Column(Text, nullable=True)  # URL для thumbnail
    large_webp_url = Column(Text, nullable=True)  # URL для large WebP
    medium_webp_url = Column(Text, nullable=True)  # URL для medium WebP
    thumbnail_webp_url = Column(Text, nullable=True)  # URL для thumbnail WebP
    
    # Метаданные
    original_width = Column(Integer, nullable=True)
    original_height = Column(Integer, nullable=True)
    original_size_bytes = Column(Integer, nullable=True)
    
    # Ошибки
    error_message = Column(Text, nullable=True)
    
    created_at = Column(DateTime, server_default=func.now(), index=True)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
    completed_at = Column(DateTime, nullable=True)

