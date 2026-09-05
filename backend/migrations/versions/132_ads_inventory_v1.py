"""First-party ad campaigns, creatives, and delivery event tables.

Revision ID: 132_ads_inventory_v1
Revises: 131_flex_messenger_tail_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "132_ads_inventory_v1"
down_revision = "131_flex_messenger_tail_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    tables = set(inspector.get_table_names())
    if "ad_campaigns" in tables:
        return

    op.create_table(
        "ad_campaigns",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("advertiser_id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=80), nullable=False),
        sa.Column("status", sa.String(length=24), nullable=False, server_default="draft"),
        sa.Column("surfaces", sa.JSON(), nullable=False),
        sa.Column("destination_type", sa.String(length=16), nullable=False, server_default="url"),
        sa.Column("destination_url", sa.Text(), nullable=True),
        sa.Column("destination_channel_id", sa.Integer(), nullable=True),
        sa.Column("destination_post_id", sa.Integer(), nullable=True),
        sa.Column("starts_at", sa.DateTime(), nullable=True),
        sa.Column("ends_at", sa.DateTime(), nullable=True),
        sa.Column("daily_cap", sa.Integer(), nullable=True),
        sa.Column("rejection_reason", sa.Text(), nullable=True),
        sa.Column("reviewed_by_user_id", sa.Integer(), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.func.now()),
        sa.ForeignKeyConstraint(
            ["advertiser_id"], ["users.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["destination_channel_id"], ["channels.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["destination_post_id"], ["posts.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["reviewed_by_user_id"], ["users.id"], ondelete="SET NULL"
        ),
    )
    op.create_index("ix_ad_campaigns_advertiser_id", "ad_campaigns", ["advertiser_id"])
    op.create_index("ix_ad_campaigns_status", "ad_campaigns", ["status"])
    op.create_index("ix_ad_campaigns_starts_at", "ad_campaigns", ["starts_at"])
    op.create_index("ix_ad_campaigns_ends_at", "ad_campaigns", ["ends_at"])
    op.create_index("ix_ad_campaigns_created_at", "ad_campaigns", ["created_at"])
    op.create_index(
        "ix_ad_campaigns_destination_channel_id",
        "ad_campaigns",
        ["destination_channel_id"],
    )
    op.create_index(
        "ix_ad_campaigns_destination_post_id",
        "ad_campaigns",
        ["destination_post_id"],
    )

    op.create_table(
        "ad_creatives",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("campaign_id", sa.Integer(), nullable=False),
        sa.Column("title", sa.String(length=80), nullable=False, server_default=""),
        sa.Column("body", sa.String(length=500), nullable=False, server_default=""),
        sa.Column("cta_label", sa.String(length=32), nullable=False, server_default="Подробнее"),
        sa.Column("image_url", sa.Text(), nullable=True),
        sa.Column("video_url", sa.Text(), nullable=True),
        sa.Column("advertiser_name", sa.String(length=80), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.func.now()),
        sa.ForeignKeyConstraint(
            ["campaign_id"], ["ad_campaigns.id"], ondelete="CASCADE"
        ),
    )
    op.create_index("ix_ad_creatives_campaign_id", "ad_creatives", ["campaign_id"])

    op.create_table(
        "ad_impressions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("campaign_id", sa.Integer(), nullable=False),
        sa.Column("creative_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("surface", sa.String(length=16), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(
            ["campaign_id"], ["ad_campaigns.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["creative_id"], ["ad_creatives.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_ad_impressions_campaign_id", "ad_impressions", ["campaign_id"])
    op.create_index("ix_ad_impressions_creative_id", "ad_impressions", ["creative_id"])
    op.create_index("ix_ad_impressions_user_id", "ad_impressions", ["user_id"])
    op.create_index("ix_ad_impressions_surface", "ad_impressions", ["surface"])
    op.create_index("ix_ad_impressions_created_at", "ad_impressions", ["created_at"])

    op.create_table(
        "ad_clicks",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("campaign_id", sa.Integer(), nullable=False),
        sa.Column("creative_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("surface", sa.String(length=16), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(
            ["campaign_id"], ["ad_campaigns.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["creative_id"], ["ad_creatives.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_ad_clicks_campaign_id", "ad_clicks", ["campaign_id"])
    op.create_index("ix_ad_clicks_creative_id", "ad_clicks", ["creative_id"])
    op.create_index("ix_ad_clicks_user_id", "ad_clicks", ["user_id"])
    op.create_index("ix_ad_clicks_surface", "ad_clicks", ["surface"])
    op.create_index("ix_ad_clicks_created_at", "ad_clicks", ["created_at"])

    op.create_table(
        "ad_hides",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("campaign_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.Column("hidden", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.ForeignKeyConstraint(
            ["campaign_id"], ["ad_campaigns.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("campaign_id", "user_id", name="uq_ad_hide_user_campaign"),
    )
    op.create_index("ix_ad_hides_campaign_id", "ad_hides", ["campaign_id"])
    op.create_index("ix_ad_hides_user_id", "ad_hides", ["user_id"])


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    tables = set(inspector.get_table_names())
    if "ad_hides" in tables:
        op.drop_index("ix_ad_hides_user_id", table_name="ad_hides")
        op.drop_index("ix_ad_hides_campaign_id", table_name="ad_hides")
        op.drop_table("ad_hides")
    if "ad_clicks" in tables:
        op.drop_index("ix_ad_clicks_created_at", table_name="ad_clicks")
        op.drop_index("ix_ad_clicks_surface", table_name="ad_clicks")
        op.drop_index("ix_ad_clicks_user_id", table_name="ad_clicks")
        op.drop_index("ix_ad_clicks_creative_id", table_name="ad_clicks")
        op.drop_index("ix_ad_clicks_campaign_id", table_name="ad_clicks")
        op.drop_table("ad_clicks")
    if "ad_impressions" in tables:
        op.drop_index("ix_ad_impressions_created_at", table_name="ad_impressions")
        op.drop_index("ix_ad_impressions_surface", table_name="ad_impressions")
        op.drop_index("ix_ad_impressions_user_id", table_name="ad_impressions")
        op.drop_index("ix_ad_impressions_creative_id", table_name="ad_impressions")
        op.drop_index("ix_ad_impressions_campaign_id", table_name="ad_impressions")
        op.drop_table("ad_impressions")
    if "ad_creatives" in tables:
        op.drop_index("ix_ad_creatives_campaign_id", table_name="ad_creatives")
        op.drop_table("ad_creatives")
    if "ad_campaigns" in tables:
        op.drop_index("ix_ad_campaigns_destination_post_id", table_name="ad_campaigns")
        op.drop_index("ix_ad_campaigns_destination_channel_id", table_name="ad_campaigns")
        op.drop_index("ix_ad_campaigns_created_at", table_name="ad_campaigns")
        op.drop_index("ix_ad_campaigns_ends_at", table_name="ad_campaigns")
        op.drop_index("ix_ad_campaigns_starts_at", table_name="ad_campaigns")
        op.drop_index("ix_ad_campaigns_status", table_name="ad_campaigns")
        op.drop_index("ix_ad_campaigns_advertiser_id", table_name="ad_campaigns")
        op.drop_table("ad_campaigns")
