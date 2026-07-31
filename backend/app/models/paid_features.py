"""Telegram-like paid feature models: stars, purchases, paid channels, boosts."""
from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    UniqueConstraint,
    JSON,
)
from sqlalchemy.sql import func

from app.core.database import Base


class StarTransaction(Base):
    __tablename__ = "star_transactions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    counterparty_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    amount = Column(Integer, nullable=False)
    type = Column(String(32), nullable=False, index=True)  # purchase | content_purchase | donation | boost | refund | admin_adjust
    status = Column(String(24), nullable=False, default="completed", index=True)
    reference_type = Column(String(32), nullable=True, index=True)
    reference_id = Column(Integer, nullable=True, index=True)
    provider = Column(String(32), nullable=True)
    provider_payment_id = Column(String(128), nullable=True, index=True)
    idempotency_key = Column(String(128), nullable=True, unique=True)
    meta = Column(JSON, nullable=True)
    created_at = Column(DateTime, server_default=func.now(), nullable=False, index=True)


class PaidContentPurchase(Base):
    __tablename__ = "paid_content_purchases"
    __table_args__ = (
        UniqueConstraint("user_id", "post_id", name="uq_paid_content_user_post"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    post_id = Column(Integer, ForeignKey("posts.id", ondelete="CASCADE"), nullable=False, index=True)
    author_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    amount_stars = Column(Integer, nullable=False)
    status = Column(String(24), nullable=False, default="completed", index=True)
    created_at = Column(DateTime, server_default=func.now(), nullable=False, index=True)


class CreatorBalance(Base):
    __tablename__ = "creator_balances"

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    available_stars = Column(Integer, nullable=False, default=0)
    pending_stars = Column(Integer, nullable=False, default=0)
    paid_out_stars = Column(Integer, nullable=False, default=0)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class PaidChannelSubscription(Base):
    __tablename__ = "paid_channel_subscriptions"
    __table_args__ = (
        UniqueConstraint("user_id", "channel_id", name="uq_paid_channel_user_channel"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    channel_id = Column(Integer, ForeignKey("channels.id", ondelete="CASCADE"), nullable=False, index=True)
    amount_stars = Column(Integer, nullable=False)
    status = Column(String(24), nullable=False, default="active", index=True)
    started_at = Column(DateTime, server_default=func.now(), nullable=False)
    expires_at = Column(DateTime, nullable=True, index=True)
    auto_renew = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime, server_default=func.now(), nullable=False, index=True)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class PostBoost(Base):
    __tablename__ = "post_boosts"

    id = Column(Integer, primary_key=True, index=True)
    post_id = Column(Integer, ForeignKey("posts.id", ondelete="CASCADE"), nullable=False, index=True)
    buyer_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    amount_stars = Column(Integer, nullable=False)
    duration_days = Column(Integer, nullable=False, default=7)
    status = Column(String(24), nullable=False, default="active", index=True)
    impressions = Column(Integer, nullable=False, default=0)
    clicks = Column(Integer, nullable=False, default=0)
    starts_at = Column(DateTime, server_default=func.now(), nullable=False)
    expires_at = Column(DateTime, nullable=True, index=True)
    created_at = Column(DateTime, server_default=func.now(), nullable=False, index=True)


class CreatorPayoutRequest(Base):
    __tablename__ = "creator_payout_requests"

    id = Column(Integer, primary_key=True, index=True)
    creator_user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    amount_stars = Column(Integer, nullable=False)
    amount_rub = Column(Numeric(12, 2), nullable=False)
    status = Column(String(24), nullable=False, default="pending", index=True)  # pending|approved|rejected|paid
    note = Column(String(512), nullable=True)
    reviewed_by_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    reviewed_at = Column(DateTime, nullable=True)
    paid_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, server_default=func.now(), nullable=False, index=True)


class PaidMessageUnlock(Base):
    """Unlock of a paid chat media message (Telegram paid media)."""

    __tablename__ = "paid_message_unlocks"
    __table_args__ = (
        UniqueConstraint("user_id", "message_id", name="uq_paid_message_unlock_user_msg"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    message_id = Column(Integer, ForeignKey("messages.id", ondelete="CASCADE"), nullable=False, index=True)
    author_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    amount_stars = Column(Integer, nullable=False)
    status = Column(String(24), nullable=False, default="completed", index=True)
    created_at = Column(DateTime, server_default=func.now(), nullable=False, index=True)


class StarGift(Base):
    """Catalog of Telegram-like star gifts."""

    __tablename__ = "star_gifts"

    id = Column(Integer, primary_key=True, index=True)
    slug = Column(String(64), nullable=False, unique=True)
    title = Column(String(120), nullable=False)
    emoji = Column(String(16), nullable=False, default="🎁")
    stars = Column(Integer, nullable=False)
    is_active = Column(Boolean, nullable=False, default=True, index=True)
    sort_order = Column(Integer, nullable=False, default=0, index=True)
    created_at = Column(DateTime, server_default=func.now(), nullable=False)

