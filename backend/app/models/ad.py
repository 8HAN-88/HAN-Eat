"""First-party ad inventory: campaigns, creatives, and later delivery events."""
from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    JSON,
)
from sqlalchemy.sql import func

from app.core.database import Base


class AdCampaign(Base):
    __tablename__ = "ad_campaigns"

    id = Column(Integer, primary_key=True, index=True)
    advertiser_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name = Column(String(80), nullable=False)
    status = Column(String(24), nullable=False, default="draft", index=True)
    surfaces = Column(JSON, nullable=False, default=list)
    destination_type = Column(String(16), nullable=False, default="url")
    destination_url = Column(Text, nullable=True)
    destination_channel_id = Column(
        Integer,
        ForeignKey("channels.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    destination_post_id = Column(
        Integer,
        ForeignKey("posts.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    starts_at = Column(DateTime, nullable=True, index=True)
    ends_at = Column(DateTime, nullable=True, index=True)
    daily_cap = Column(Integer, nullable=True)
    rejection_reason = Column(Text, nullable=True)
    reviewed_by_user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    reviewed_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, server_default=func.now(), nullable=False, index=True)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class AdCreative(Base):
    __tablename__ = "ad_creatives"

    id = Column(Integer, primary_key=True, index=True)
    campaign_id = Column(
        Integer,
        ForeignKey("ad_campaigns.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    title = Column(String(80), nullable=False, default="")
    body = Column(String(500), nullable=False, default="")
    cta_label = Column(String(32), nullable=False, default="Подробнее")
    image_url = Column(Text, nullable=True)
    video_url = Column(Text, nullable=True)
    advertiser_name = Column(String(80), nullable=True)
    created_at = Column(DateTime, server_default=func.now(), nullable=False)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class AdImpression(Base):
    __tablename__ = "ad_impressions"

    id = Column(Integer, primary_key=True, index=True)
    campaign_id = Column(
        Integer,
        ForeignKey("ad_campaigns.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    creative_id = Column(
        Integer,
        ForeignKey("ad_creatives.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    surface = Column(String(16), nullable=False, index=True)
    created_at = Column(DateTime, server_default=func.now(), nullable=False, index=True)


class AdClick(Base):
    __tablename__ = "ad_clicks"

    id = Column(Integer, primary_key=True, index=True)
    campaign_id = Column(
        Integer,
        ForeignKey("ad_campaigns.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    creative_id = Column(
        Integer,
        ForeignKey("ad_creatives.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    surface = Column(String(16), nullable=False, index=True)
    created_at = Column(DateTime, server_default=func.now(), nullable=False, index=True)


class AdHide(Base):
    __tablename__ = "ad_hides"
    __table_args__ = (
        UniqueConstraint("campaign_id", "user_id", name="uq_ad_hide_user_campaign"),
    )

    id = Column(Integer, primary_key=True, index=True)
    campaign_id = Column(
        Integer,
        ForeignKey("ad_campaigns.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    created_at = Column(DateTime, server_default=func.now(), nullable=False, index=True)
    # Reserved for later hide/report UX.
    hidden = Column(Boolean, nullable=False, default=True)
