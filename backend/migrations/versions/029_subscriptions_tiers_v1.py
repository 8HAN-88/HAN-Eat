"""Subscription tiers V1: ai, creator, pro

Revision ID: 029_subscriptions_tiers_v1
Revises: 028_moderation_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "029_subscriptions_tiers_v1"
down_revision = "028_moderation_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "subscriptions",
        sa.Column("product", sa.String(20), nullable=False, server_default="pro"),
    )
    op.add_column(
        "users",
        sa.Column(
            "subscription_status",
            sa.String(20),
            nullable=False,
            server_default="active",
        ),
    )
    op.add_column(
        "users",
        sa.Column("subscription_platform", sa.String(20), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column(
            "subscription_auto_renew",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )
    # Legacy plus → pro
    op.execute("UPDATE users SET subscription_type = 'pro' WHERE subscription_type = 'plus'")


def downgrade() -> None:
    op.execute("UPDATE users SET subscription_type = 'plus' WHERE subscription_type = 'pro'")
    op.drop_column("users", "subscription_auto_renew")
    op.drop_column("users", "subscription_platform")
    op.drop_column("users", "subscription_status")
    op.drop_column("subscriptions", "product")
