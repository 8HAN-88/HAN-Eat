"""Cloud GIF favorites (Telegram Premium)."""

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.sql import func

from app.core.database import Base


class GifFavorite(Base):
    __tablename__ = "gif_favorites"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    media_url = Column(String(1024), nullable=False)
    preview_url = Column(String(1024), nullable=True)
    title = Column(String(80), nullable=True)
    created_at = Column(DateTime, server_default=func.now(), index=True)

    __table_args__ = (
        UniqueConstraint("user_id", "media_url", name="uq_gif_favorite_user_url"),
    )
