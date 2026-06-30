"""
Модель команд бота (BotFather)
"""
from sqlalchemy import Column, Integer, String, ForeignKey, Text
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from app.core.database import Base


class BotCommand(Base):
    __tablename__ = "bot_commands"

    id = Column(Integer, primary_key=True, index=True)
    bot_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    command = Column(String(32), nullable=False)
    description = Column(String(256), nullable=False)

    created_at = Column(DateTime, server_default=func.now())

    # Relationship (optional, for convenience)
    # bot = relationship("User", back_populates="bot_commands")
