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


class StickerPack(Base):
    __tablename__ = "sticker_packs"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(120), nullable=False)
    slug = Column(String(140), nullable=False, unique=True, index=True)
    owner_user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    is_public = Column(Boolean, nullable=False, default=True, index=True)
    is_premium = Column(Boolean, nullable=False, default=False, index=True)
    price_stars = Column(Integer, nullable=False, default=0, index=True)
    listed_at = Column(DateTime, nullable=True, index=True)
    created_at = Column(DateTime, server_default=func.now(), index=True)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class Sticker(Base):
    __tablename__ = "stickers"

    id = Column(Integer, primary_key=True, index=True)
    pack_id = Column(
        Integer,
        ForeignKey("sticker_packs.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    media_url = Column(String(512), nullable=False)
    emoji = Column(String(32), nullable=True)
    sticker_type = Column(String(16), nullable=False, default="static", index=True)
    order_index = Column(Integer, nullable=False, default=0, index=True)
    created_at = Column(DateTime, server_default=func.now(), index=True)


class StickerPackInstall(Base):
    __tablename__ = "sticker_pack_installs"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    pack_id = Column(
        Integer,
        ForeignKey("sticker_packs.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    created_at = Column(DateTime, server_default=func.now(), index=True)

    __table_args__ = (
        UniqueConstraint("user_id", "pack_id", name="uq_sticker_pack_install"),
    )


class StickerFavorite(Base):
    __tablename__ = "sticker_favorites"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    sticker_id = Column(
        Integer,
        ForeignKey("stickers.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    created_at = Column(DateTime, server_default=func.now(), index=True)

    __table_args__ = (
        UniqueConstraint(
            "user_id", "sticker_id", name="uq_sticker_favorite_user_sticker"
        ),
    )


class StickerPackPin(Base):
    __tablename__ = "sticker_pack_pins"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    pack_id = Column(
        Integer,
        ForeignKey("sticker_packs.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    pin_order = Column(Integer, nullable=False, default=0, index=True)
    created_at = Column(DateTime, server_default=func.now(), index=True)

    __table_args__ = (
        UniqueConstraint("user_id", "pack_id", name="uq_sticker_pack_pin_user_pack"),
    )


class StickerPackPurchase(Base):
    __tablename__ = "sticker_pack_purchases"

    id = Column(Integer, primary_key=True)
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    pack_id = Column(
        Integer,
        ForeignKey("sticker_packs.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    seller_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    amount_stars = Column(Integer, nullable=False, default=0)
    fee_stars = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint("user_id", "pack_id", name="uq_sticker_pack_purchase"),
    )
