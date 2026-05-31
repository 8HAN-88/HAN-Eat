"""
Модель участника канала
"""
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Boolean
from sqlalchemy.sql import func
from app.core.database import Base


class ChannelMember(Base):
    __tablename__ = "channel_members"
    
    id = Column(Integer, primary_key=True, index=True)
    channel_id = Column(Integer, ForeignKey("channels.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    role = Column(String(20), default="member")  # owner | admin | moderator | member
    # active — полный доступ; pending — заявка в приватный канал
    status = Column(String(20), default="active", nullable=False, index=True)
    # owner определяется через admin_user_id в channels, но для удобства может быть и здесь
    is_favorite = Column(Boolean, default=False, nullable=False)  # Избранный канал
    # Push / in-app уведомления о постах канала (false = «без звука»)
    notifications_enabled = Column(Boolean, default=True, nullable=False)
    joined_at = Column(DateTime, server_default=func.now())
    
    # Уникальный индекс: один пользователь может быть только один раз в канале
    __table_args__ = (
        {'sqlite_autoincrement': True},
    )

