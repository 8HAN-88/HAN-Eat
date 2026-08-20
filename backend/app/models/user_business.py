"""Telegram Business settings and auto-reply cooldown."""

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.sql import func

from app.core.database import Base


class UserBusinessSettings(Base):
    __tablename__ = "user_business_settings"

    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    greeting_enabled = Column(Boolean, nullable=False, default=False)
    greeting_text = Column(String(400), nullable=True)
    greeting_inactivity_days = Column(Integer, nullable=False, default=7)
    away_enabled = Column(Boolean, nullable=False, default=False)
    away_text = Column(String(400), nullable=True)
    away_mode = Column(String(20), nullable=False, default="manual")
    hours_json = Column(Text, nullable=True)
    location_lat = Column(Float, nullable=True)
    location_lng = Column(Float, nullable=True)
    location_address = Column(String(120), nullable=True)
    intro_title = Column(String(40), nullable=True)
    intro_text = Column(String(200), nullable=True)
    intro_sticker_url = Column(String(1024), nullable=True)
    support_bot_id = Column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    website_url = Column(String(200), nullable=True)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class BusinessAutoReply(Base):
    __tablename__ = "business_auto_replies"

    id = Column(Integer, primary_key=True)
    owner_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    peer_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    kind = Column(String(16), nullable=False)
    sent_at = Column(DateTime, server_default=func.now(), nullable=False)

    __table_args__ = (
        UniqueConstraint(
            "owner_user_id", "peer_user_id", "kind", name="uq_business_auto_reply"
        ),
    )
