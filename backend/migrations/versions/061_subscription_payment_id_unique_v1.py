"""Unique provider payment id for subscriptions

Revision ID: 061_sub_payment_unique_v1
Revises: 060_telegram_paid_features_v1
"""
from alembic import op

revision = "061_sub_payment_unique_v1"
down_revision = "060_telegram_paid_features_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        UPDATE subscriptions
        SET payment_provider_subscription_id = NULL
        WHERE payment_provider_subscription_id = ''
        """
    )
    op.execute(
        """
        WITH ranked AS (
            SELECT
                id,
                ROW_NUMBER() OVER (
                    PARTITION BY payment_provider, payment_provider_subscription_id
                    ORDER BY created_at DESC NULLS LAST, id DESC
                ) AS duplicate_rank
            FROM subscriptions
            WHERE payment_provider IS NOT NULL
              AND payment_provider_subscription_id IS NOT NULL
        )
        UPDATE subscriptions AS subscriptions_table
        SET payment_provider_subscription_id = NULL
        FROM ranked
        WHERE subscriptions_table.id = ranked.id
          AND ranked.duplicate_rank > 1
        """
    )
    op.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS uq_subscriptions_provider_payment_id
        ON subscriptions (payment_provider, payment_provider_subscription_id)
        """
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS uq_subscriptions_provider_payment_id")
