"""Модели мини-приложений HanWe (аналог Telegram Mini Apps)."""
from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.sql import func

from app.core.database import Base


class BotMiniApp(Base):
    __tablename__ = "bot_miniapps"

    id = Column(Integer, primary_key=True, index=True)
    bot_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name = Column(String(64), nullable=False)
    short_name = Column(String(32), nullable=False)
    description = Column(String(512), nullable=True)
    # tools | games | entertainment | shopping | other
    category = Column(String(32), nullable=True)
    url = Column(Text, nullable=False)
    icon_url = Column(Text, nullable=True)
    is_builtin = Column(Boolean, default=False, nullable=False)
    is_official = Column(Boolean, default=False, nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    moderation_status = Column(String(16), default="pending", nullable=False)
    moderation_note = Column(String(512), nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        UniqueConstraint("bot_id", "short_name", name="uq_bot_miniapps_short_name"),
    )


class MiniAppInstall(Base):
    __tablename__ = "miniapp_installs"

    id = Column(Integer, primary_key=True, index=True)
    miniapp_id = Column(
        Integer, ForeignKey("bot_miniapps.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    installed_at = Column(DateTime, server_default=func.now())
    last_launched_at = Column(DateTime, nullable=True)

    __table_args__ = (
        UniqueConstraint("miniapp_id", "user_id", name="uq_miniapp_installs_user_app"),
    )


class MiniAppLaunch(Base):
    __tablename__ = "miniapp_launches"

    id = Column(Integer, primary_key=True, index=True)
    miniapp_id = Column(
        Integer, ForeignKey("bot_miniapps.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    conversation_id = Column(Integer, nullable=True, index=True)
    launched_at = Column(DateTime, server_default=func.now(), index=True)
