"""Unique provider payment id for subscriptions

Revision ID: 061_subscription_payment_id_unique_v1
Revises: 060_telegram_paid_features_v1
"""
from alembic import op

revision = "061_subscription_payment_id_unique_v1"
down_revision = "060_telegram_paid_features_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_index(
        "uq_subscriptions_provider_payment_id",
        "subscriptions",
        ["payment_provider", "payment_provider_subscription_id"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index("uq_subscriptions_provider_payment_id", table_name="subscriptions")
