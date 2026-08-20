"""Share tokens for chat folders (Telegram Premium)."""

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String
from sqlalchemy.sql import func

from app.core.database import Base


class ChatFolderShare(Base):
    __tablename__ = "chat_folder_shares"

    id = Column(Integer, primary_key=True, index=True)
    token = Column(String(64), nullable=False, unique=True, index=True)
    folder_id = Column(
        Integer, ForeignKey("chat_folders.id", ondelete="CASCADE"), nullable=False, index=True
    )
    owner_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    created_at = Column(DateTime, server_default=func.now())
    revoked_at = Column(DateTime, nullable=True)
