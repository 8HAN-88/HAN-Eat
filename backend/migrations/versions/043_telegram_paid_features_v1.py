"""Telegram-like paid features: stars, paid content, paid channels, boosts

Revision ID: 043_telegram_paid_features_v1
Revises: 042_subscription_promises_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "043_telegram_paid_features_v1"
down_revision = "042_subscription_promises_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("posts", sa.Column("is_paid", sa.Boolean(), nullable=False, server_default="false"))
    op.add_column("posts", sa.Column("price_stars", sa.Integer(), nullable=False, server_default="0"))
    op.add_column("posts", sa.Column("preview_mode", sa.String(20), nullable=False, server_default="teaser"))
    op.create_index("ix_posts_is_paid", "posts", ["is_paid"])

    op.add_column("channels", sa.Column("is_paid", sa.Boolean(), nullable=False, server_default="false"))
    op.add_column("channels", sa.Column("monthly_price_stars", sa.Integer(), nullable=False, server_default="0"))
    op.create_index("ix_channels_is_paid", "channels", ["is_paid"])

    op.create_table(
        "star_transactions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("counterparty_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("amount", sa.Integer(), nullable=False),
        sa.Column("type", sa.String(32), nullable=False),
        sa.Column("status", sa.String(24), nullable=False, server_default="completed"),
        sa.Column("reference_type", sa.String(32), nullable=True),
        sa.Column("reference_id", sa.Integer(), nullable=True),
        sa.Column("provider", sa.String(32), nullable=True),
        sa.Column("provider_payment_id", sa.String(128), nullable=True),
        sa.Column("idempotency_key", sa.String(128), nullable=True),
        sa.Column("meta", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_star_transactions_user_id", "star_transactions", ["user_id"])
    op.create_index("ix_star_transactions_counterparty_user_id", "star_transactions", ["counterparty_user_id"])
    op.create_index("ix_star_transactions_type", "star_transactions", ["type"])
    op.create_index("ix_star_transactions_status", "star_transactions", ["status"])
    op.create_index("ix_star_transactions_reference_type", "star_transactions", ["reference_type"])
    op.create_index("ix_star_transactions_reference_id", "star_transactions", ["reference_id"])
    op.create_index("ix_star_transactions_provider_payment_id", "star_transactions", ["provider_payment_id"])
    op.create_index("ix_star_transactions_created_at", "star_transactions", ["created_at"])
    op.create_unique_constraint("uq_star_transactions_idempotency_key", "star_transactions", ["idempotency_key"])

    op.create_table(
        "paid_content_purchases",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("post_id", sa.Integer(), sa.ForeignKey("posts.id", ondelete="CASCADE"), nullable=False),
        sa.Column("author_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("amount_stars", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(24), nullable=False, server_default="completed"),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("user_id", "post_id", name="uq_paid_content_user_post"),
    )
    op.create_index("ix_paid_content_purchases_user_id", "paid_content_purchases", ["user_id"])
    op.create_index("ix_paid_content_purchases_post_id", "paid_content_purchases", ["post_id"])
    op.create_index("ix_paid_content_purchases_author_id", "paid_content_purchases", ["author_id"])
    op.create_index("ix_paid_content_purchases_status", "paid_content_purchases", ["status"])
    op.create_index("ix_paid_content_purchases_created_at", "paid_content_purchases", ["created_at"])

    op.create_table(
        "creator_balances",
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("available_stars", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("pending_stars", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("paid_out_stars", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.func.now(), nullable=True),
    )

    op.create_table(
        "paid_channel_subscriptions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("channel_id", sa.Integer(), sa.ForeignKey("channels.id", ondelete="CASCADE"), nullable=False),
        sa.Column("amount_stars", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(24), nullable=False, server_default="active"),
        sa.Column("started_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=True),
        sa.Column("auto_renew", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.func.now(), nullable=True),
        sa.UniqueConstraint("user_id", "channel_id", name="uq_paid_channel_user_channel"),
    )
    op.create_index("ix_paid_channel_subscriptions_user_id", "paid_channel_subscriptions", ["user_id"])
    op.create_index("ix_paid_channel_subscriptions_channel_id", "paid_channel_subscriptions", ["channel_id"])
    op.create_index("ix_paid_channel_subscriptions_status", "paid_channel_subscriptions", ["status"])
    op.create_index("ix_paid_channel_subscriptions_expires_at", "paid_channel_subscriptions", ["expires_at"])
    op.create_index("ix_paid_channel_subscriptions_created_at", "paid_channel_subscriptions", ["created_at"])

    op.create_table(
        "post_boosts",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("post_id", sa.Integer(), sa.ForeignKey("posts.id", ondelete="CASCADE"), nullable=False),
        sa.Column("buyer_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("amount_stars", sa.Integer(), nullable=False),
        sa.Column("duration_days", sa.Integer(), nullable=False, server_default="7"),
        sa.Column("status", sa.String(24), nullable=False, server_default="active"),
        sa.Column("impressions", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("clicks", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("starts_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_post_boosts_post_id", "post_boosts", ["post_id"])
    op.create_index("ix_post_boosts_buyer_id", "post_boosts", ["buyer_id"])
    op.create_index("ix_post_boosts_status", "post_boosts", ["status"])
    op.create_index("ix_post_boosts_expires_at", "post_boosts", ["expires_at"])
    op.create_index("ix_post_boosts_created_at", "post_boosts", ["created_at"])


def downgrade() -> None:
    op.drop_index("ix_post_boosts_created_at", table_name="post_boosts")
    op.drop_index("ix_post_boosts_expires_at", table_name="post_boosts")
    op.drop_index("ix_post_boosts_status", table_name="post_boosts")
    op.drop_index("ix_post_boosts_buyer_id", table_name="post_boosts")
    op.drop_index("ix_post_boosts_post_id", table_name="post_boosts")
    op.drop_table("post_boosts")

    op.drop_index("ix_paid_channel_subscriptions_created_at", table_name="paid_channel_subscriptions")
    op.drop_index("ix_paid_channel_subscriptions_expires_at", table_name="paid_channel_subscriptions")
    op.drop_index("ix_paid_channel_subscriptions_status", table_name="paid_channel_subscriptions")
    op.drop_index("ix_paid_channel_subscriptions_channel_id", table_name="paid_channel_subscriptions")
    op.drop_index("ix_paid_channel_subscriptions_user_id", table_name="paid_channel_subscriptions")
    op.drop_table("paid_channel_subscriptions")

    op.drop_table("creator_balances")

    op.drop_index("ix_paid_content_purchases_created_at", table_name="paid_content_purchases")
    op.drop_index("ix_paid_content_purchases_status", table_name="paid_content_purchases")
    op.drop_index("ix_paid_content_purchases_author_id", table_name="paid_content_purchases")
    op.drop_index("ix_paid_content_purchases_post_id", table_name="paid_content_purchases")
    op.drop_index("ix_paid_content_purchases_user_id", table_name="paid_content_purchases")
    op.drop_table("paid_content_purchases")

    op.drop_constraint("uq_star_transactions_idempotency_key", "star_transactions", type_="unique")
    op.drop_index("ix_star_transactions_created_at", table_name="star_transactions")
    op.drop_index("ix_star_transactions_provider_payment_id", table_name="star_transactions")
    op.drop_index("ix_star_transactions_reference_id", table_name="star_transactions")
    op.drop_index("ix_star_transactions_reference_type", table_name="star_transactions")
    op.drop_index("ix_star_transactions_status", table_name="star_transactions")
    op.drop_index("ix_star_transactions_type", table_name="star_transactions")
    op.drop_index("ix_star_transactions_counterparty_user_id", table_name="star_transactions")
    op.drop_index("ix_star_transactions_user_id", table_name="star_transactions")
    op.drop_table("star_transactions")

    op.drop_index("ix_channels_is_paid", table_name="channels")
    op.drop_column("channels", "monthly_price_stars")
    op.drop_column("channels", "is_paid")
    op.drop_index("ix_posts_is_paid", table_name="posts")
    op.drop_column("posts", "preview_mode")
    op.drop_column("posts", "price_stars")
    op.drop_column("posts", "is_paid")

