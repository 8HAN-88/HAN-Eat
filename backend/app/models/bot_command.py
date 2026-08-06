"""
Модель команд бота (BotFather)
"""
from sqlalchemy import Column, Integer, String, Boolean, ForeignKey, DateTime
from sqlalchemy.sql import func
from app.core.database import Base


class BotCommand(Base):
    __tablename__ = "bot_commands"

    id = Column(Integer, primary_key=True, index=True)
    bot_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    command = Column(String(32), nullable=False)
    description = Column(String(256), nullable=False)
    response_text = Column(String(2000), nullable=True)
    inline_buttons_json = Column(String(4000), nullable=True)
    reply_buttons_json = Column(String(4000), nullable=True)
    reply_keyboard_one_time = Column(Boolean, default=False, nullable=False)
    reply_keyboard_resize = Column(Boolean, default=True, nullable=False)
    reply_keyboard_placeholder = Column(String(64), nullable=True)
    remove_reply_keyboard = Column(Boolean, default=False, nullable=False)

    created_at = Column(DateTime, server_default=func.now())
