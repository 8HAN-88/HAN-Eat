"""Папки чатов (как в Telegram)."""
from sqlalchemy import (
    CheckConstraint,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.sql import func

from app.core.database import Base


class ChatFolder(Base):
    __tablename__ = "chat_folders"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name = Column(String(64), nullable=False)
    icon = Column(String(8), nullable=True)
    position = Column(Integer, nullable=False, default=0)
    filters_json = Column(String(2048), nullable=True)
    created_at = Column(DateTime, server_default=func.now())


class ChatFolderItem(Base):
    __tablename__ = "chat_folder_items"

    id = Column(Integer, primary_key=True, index=True)
    folder_id = Column(
        Integer, ForeignKey("chat_folders.id", ondelete="CASCADE"), nullable=False, index=True
    )
    conversation_id = Column(
        Integer, ForeignKey("conversations.id", ondelete="CASCADE"), nullable=True, index=True
    )
    channel_id = Column(
        Integer, ForeignKey("channels.id", ondelete="CASCADE"), nullable=True, index=True
    )

    __table_args__ = (
        CheckConstraint(
            "(conversation_id IS NOT NULL AND channel_id IS NULL) OR "
            "(conversation_id IS NULL AND channel_id IS NOT NULL)",
            name="check_chat_folder_item_target",
        ),
        UniqueConstraint("folder_id", "conversation_id", name="uq_chat_folder_conversation"),
        UniqueConstraint("folder_id", "channel_id", name="uq_chat_folder_channel"),
    )
