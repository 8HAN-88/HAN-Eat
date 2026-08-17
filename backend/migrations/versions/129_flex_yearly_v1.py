"""Flex yearly plan on user_flex_subscriptions.

Revision ID: 129_flex_yearly_v1
Revises: 128_flex_billing_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "129_flex_yearly_v1"
down_revision = "128_flex_billing_v1"
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
    if not _column_exists("user_flex_subscriptions", "plan"):
        op.add_column(
            "user_flex_subscriptions",
            sa.Column("plan", sa.String(length=20), nullable=False, server_default="monthly"),
        )
    if not _column_exists("user_flex_subscriptions", "pending_plan"):
        op.add_column(
            "user_flex_subscriptions",
            sa.Column("pending_plan", sa.String(length=20), nullable=True),
        )


def downgrade() -> None:
    if not _table_exists("user_flex_subscriptions"):
        return
    if _column_exists("user_flex_subscriptions", "pending_plan"):
        op.drop_column("user_flex_subscriptions", "pending_plan")
    if _column_exists("user_flex_subscriptions", "plan"):
        op.drop_column("user_flex_subscriptions", "plan")
