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
    """Catalog of Telegram-like star gifts (incl. limited collectibles)."""

    __tablename__ = "star_gifts"

    id = Column(Integer, primary_key=True, index=True)
    slug = Column(String(64), nullable=False, unique=True)
    title = Column(String(120), nullable=False)
    emoji = Column(String(16), nullable=False, default="🎁")
    stars = Column(Integer, nullable=False)
    is_active = Column(Boolean, nullable=False, default=True, index=True)
    sort_order = Column(Integer, nullable=False, default=0, index=True)
    is_limited = Column(Boolean, nullable=False, default=False, index=True)
    total_supply = Column(Integer, nullable=True)
    sold_count = Column(Integer, nullable=False, default=0)
    upgrade_stars = Column(Integer, nullable=False, default=0)
    transfer_stars = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, server_default=func.now(), nullable=False)


class PaidMessageException(Base):
    """Users allowed to DM the owner without paying Stars (Telegram exceptions)."""

    __tablename__ = "paid_message_exceptions"
    __table_args__ = (
        UniqueConstraint(
            "owner_id", "allowed_user_id", name="uq_paid_message_exception_pair"
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    owner_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    allowed_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    created_at = Column(DateTime, server_default=func.now(), nullable=False)


class UserStarGift(Base):
    """Received Star gift inventory (Telegram: hold / convert / show on profile)."""

    __tablename__ = "user_star_gifts"

    id = Column(Integer, primary_key=True, index=True)
    owner_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    sender_id = Column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    gift_id = Column(
        Integer, ForeignKey("star_gifts.id", ondelete="SET NULL"), nullable=True, index=True
    )
    message_id = Column(
        Integer, ForeignKey("messages.id", ondelete="SET NULL"), nullable=True, index=True
    )
    stars = Column(Integer, nullable=False)
    slug = Column(String(64), nullable=False, default="gift")
    title = Column(String(120), nullable=False, default="Подарок")
    emoji = Column(String(16), nullable=False, default="🎁")
    note = Column(String(500), nullable=True)
    # held = waiting for convert/keep; converted = Stars claimed; kept = saved on profile
    status = Column(String(24), nullable=False, default="held", index=True)
    is_displayed = Column(Boolean, nullable=False, default=True, index=True)
    is_collectible = Column(Boolean, nullable=False, default=False, index=True)
    # Telegram "Hide my name": sender hidden on the public profile gift wall.
    is_anonymous = Column(Boolean, nullable=False, default=False, index=True)
    serial = Column(Integer, nullable=True, index=True)
    transferred_from_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    # Telegram unique-gift resale: listed_stars > 0 means for sale.
    listed_stars = Column(Integer, nullable=True, index=True)
    listed_at = Column(DateTime, nullable=True)
    # Telegram "Wear": one collectible shown next to the owner's name.
    is_worn = Column(Boolean, nullable=False, default=False, index=True)
    converted_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, server_default=func.now(), nullable=False, index=True)


class StarGiveaway(Base):
    """Channel Stars giveaway (Telegram-like)."""

    __tablename__ = "star_giveaways"

    id = Column(Integer, primary_key=True, index=True)
    channel_id = Column(
        Integer, ForeignKey("channels.id", ondelete="CASCADE"), nullable=False, index=True
    )
    creator_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    prize_stars = Column(Integer, nullable=False)
    winners_count = Column(Integer, nullable=False)
    total_escrow_stars = Column(Integer, nullable=False)
    status = Column(String(24), nullable=False, default="active", index=True)
    ends_at = Column(DateTime, nullable=False, index=True)
    require_membership = Column(Boolean, nullable=False, default=True)
    participants_count = Column(Integer, nullable=False, default=0)
    title = Column(String(160), nullable=True)
    # stars | premium (HanWe Pro, Telegram Premium analog)
    prize_type = Column(String(16), nullable=False, default="stars")
    premium_months = Column(Integer, nullable=False, default=0)
    completed_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, server_default=func.now(), nullable=False, index=True)


class StarGiveawayParticipant(Base):
    __tablename__ = "star_giveaway_participants"
    __table_args__ = (
        UniqueConstraint("giveaway_id", "user_id", name="uq_star_giveaway_participant"),
    )

    id = Column(Integer, primary_key=True, index=True)
    giveaway_id = Column(
        Integer,
        ForeignKey("star_giveaways.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    is_winner = Column(Boolean, nullable=False, default=False, index=True)
    created_at = Column(DateTime, server_default=func.now(), nullable=False)


class StarInvoice(Base):
    """Bot Stars invoice (Telegram Bot Payments with Stars)."""

    __tablename__ = "star_invoices"

    id = Column(Integer, primary_key=True, index=True)
    bot_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    creator_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    payer_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    title = Column(String(160), nullable=False)
    description = Column(String(512), nullable=True)
    amount_stars = Column(Integer, nullable=False)
    payload = Column(String(256), nullable=True)
    status = Column(String(24), nullable=False, default="pending", index=True)
    expires_at = Column(DateTime, nullable=True)
    paid_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, server_default=func.now(), nullable=False, index=True)


class ChannelSuggestedPost(Base):
    """Telegram-like paid suggested post for a channel."""

    __tablename__ = "channel_suggested_posts"

    id = Column(Integer, primary_key=True, index=True)
    channel_id = Column(
        Integer, ForeignKey("channels.id", ondelete="CASCADE"), nullable=False, index=True
    )
    author_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    text = Column(String(2000), nullable=False)
    media_url = Column(String(1024), nullable=True)
    amount_stars = Column(Integer, nullable=False)
    status = Column(String(24), nullable=False, default="pending", index=True)
    post_id = Column(
        Integer, ForeignKey("posts.id", ondelete="SET NULL"), nullable=True, index=True
    )
    created_at = Column(DateTime, server_default=func.now(), nullable=False, index=True)

