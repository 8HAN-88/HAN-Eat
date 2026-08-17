"""Flex billing: scheduled downgrade and period fields.

Revision ID: 128_flex_billing_v1
Revises: 127_flex_subscription_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "128_flex_billing_v1"
down_revision = "127_flex_subscription_v1"
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def _column_exists(table_name: str, column_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if table_name not in inspector.get_table_names():
        return False
    return any(c["name"] == column_name for c in inspector.get_columns(table_name))


def upgrade() -> None:
    if not _table_exists("user_flex_subscriptions"):
        return
    if not _column_exists("user_flex_subscriptions", "pending_level"):
        op.add_column(
            "user_flex_subscriptions",
            sa.Column("pending_level", sa.Integer(), nullable=True),
        )
    if not _column_exists("user_flex_subscriptions", "pending_level_at"):
        op.add_column(
            "user_flex_subscriptions",
            sa.Column("pending_level_at", sa.DateTime(), nullable=True),
        )


def downgrade() -> None:
    if not _table_exists("user_flex_subscriptions"):
        return
    if _column_exists("user_flex_subscriptions", "pending_level_at"):
        op.drop_column("user_flex_subscriptions", "pending_level_at")
    if _column_exists("user_flex_subscriptions", "pending_level"):
        op.drop_column("user_flex_subscriptions", "pending_level")
