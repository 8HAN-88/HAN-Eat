"""Flexible leveled subscription: catalog, blocks, per-user layout."""
from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.sql import func

from app.core.database import Base


FEATURE_TYPES = ("fixed", "movable", "blocked", "premium")
FEATURE_STATUSES = ("draft", "active", "archived")


class SubscriptionFeatureBlock(Base):
    __tablename__ = "subscription_feature_blocks"

    id = Column(Integer, primary_key=True, index=True)
    key = Column(String(32), nullable=False, unique=True, index=True)
    title = Column(String(120), nullable=False)
    min_level = Column(Integer, nullable=False, default=1)
    max_level = Column(Integer, nullable=False, default=3)
    sort_order = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, server_default=func.now(), nullable=False)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class SubscriptionFeature(Base):
    __tablename__ = "subscription_features"

    id = Column(Integer, primary_key=True, index=True)
    slug = Column(String(64), nullable=False, unique=True, index=True)
    title = Column(String(160), nullable=False)
    description = Column(Text, nullable=True)
    icon = Column(String(64), nullable=True)
    price_rub = Column(Numeric(10, 2), nullable=True)
    min_level = Column(Integer, nullable=False, default=1)
    max_level = Column(Integer, nullable=False, default=10)
    default_level = Column(Integer, nullable=False, default=1)
    feature_type = Column(String(16), nullable=False, default="movable")
    movable = Column(Boolean, nullable=False, default=True)
    required = Column(Boolean, nullable=False, default=False)
    block_key = Column(String(32), nullable=True, index=True)
    launch_at = Column(DateTime, nullable=True)
    status = Column(String(16), nullable=False, default="active", index=True)
    available = Column(Boolean, nullable=False, default=True)
    sort_order = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, server_default=func.now(), nullable=False)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class UserFlexSubscription(Base):
    __tablename__ = "user_flex_subscriptions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True, index=True
    )
    current_level = Column(Integer, nullable=False, default=0)
    status = Column(String(20), nullable=False, default="inactive", index=True)
    plan = Column(String(20), nullable=False, default="monthly")
    expires_at = Column(DateTime, nullable=True, index=True)
    auto_renew = Column(Boolean, nullable=False, default=False)
    pending_level = Column(Integer, nullable=True)
    pending_level_at = Column(DateTime, nullable=True)
    pending_plan = Column(String(20), nullable=True)
    payment_subscription_id = Column(Integer, nullable=True)
    created_at = Column(DateTime, server_default=func.now(), nullable=False)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class UserFlexSlot(Base):
    __tablename__ = "user_flex_slots"
    __table_args__ = (
        UniqueConstraint("user_id", "feature_id", name="uq_flex_slot_user_feature"),
        UniqueConstraint("user_id", "assigned_level", name="uq_flex_slot_user_level"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    feature_id = Column(
        Integer,
        ForeignKey("subscription_features.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    assigned_level = Column(Integer, nullable=False)
    created_at = Column(DateTime, server_default=func.now(), nullable=False)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class UserFlexGift(Base):
    __tablename__ = "user_flex_gifts"

    id = Column(Integer, primary_key=True, index=True)
    sender_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    recipient_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    level = Column(Integer, nullable=False)
    plan = Column(String(20), nullable=False, default="monthly")
    amount = Column(Numeric(10, 2), nullable=False)
    status = Column(String(20), nullable=False, default="pending", index=True)
    payment_provider = Column(String(32), nullable=True)
    payment_id = Column(String(128), nullable=True, index=True)
    created_at = Column(DateTime, server_default=func.now(), nullable=False)
    applied_at = Column(DateTime, nullable=True)
