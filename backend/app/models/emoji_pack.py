"""User-published custom emoji packs."""

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.sql import func

from app.core.database import Base


class EmojiPack(Base):
    __tablename__ = "emoji_packs"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(120), nullable=False)
    slug = Column(String(140), nullable=False, unique=True, index=True)
    owner_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    is_public = Column(Boolean, nullable=False, default=True, index=True)
    price_stars = Column(Integer, nullable=False, default=0, index=True)
    listed_at = Column(DateTime, nullable=True, index=True)
    created_at = Column(DateTime, server_default=func.now(), index=True)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class CustomEmoji(Base):
    __tablename__ = "custom_emojis"

    id = Column(Integer, primary_key=True, index=True)
    pack_id = Column(
        Integer, ForeignKey("emoji_packs.id", ondelete="CASCADE"), nullable=False, index=True
    )
    media_url = Column(String(512), nullable=False)
    shortcode = Column(String(32), nullable=True)
    order_index = Column(Integer, nullable=False, default=0, index=True)
    created_at = Column(DateTime, server_default=func.now(), index=True)


class EmojiPackInstall(Base):
    __tablename__ = "emoji_pack_installs"

    id = Column(Integer, primary_key=True)
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    pack_id = Column(
        Integer, ForeignKey("emoji_packs.id", ondelete="CASCADE"), nullable=False, index=True
    )
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint("user_id", "pack_id", name="uq_emoji_pack_install"),
    )


class EmojiPackPurchase(Base):
    __tablename__ = "emoji_pack_purchases"

    id = Column(Integer, primary_key=True)
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    pack_id = Column(
        Integer, ForeignKey("emoji_packs.id", ondelete="CASCADE"), nullable=False, index=True
    )
    seller_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    amount_stars = Column(Integer, nullable=False, default=0)
    fee_stars = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint("user_id", "pack_id", name="uq_emoji_pack_purchase"),
    )
