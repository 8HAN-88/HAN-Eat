"""Flex gifts of a specific level.

Revision ID: 130_flex_gifts_v1
Revises: 129_flex_yearly_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "130_flex_gifts_v1"
down_revision = "129_flex_yearly_v1"
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def upgrade() -> None:
    if _table_exists("user_flex_gifts"):
        return
    op.create_table(
        "user_flex_gifts",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("sender_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column(
            "recipient_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("level", sa.Integer(), nullable=False),
        sa.Column("plan", sa.String(length=20), nullable=False, server_default="monthly"),
        sa.Column("amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="pending"),
        sa.Column("payment_provider", sa.String(length=32), nullable=True),
        sa.Column("payment_id", sa.String(length=128), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.Column("applied_at", sa.DateTime(), nullable=True),
    )
    op.create_index("ix_user_flex_gifts_sender_id", "user_flex_gifts", ["sender_id"])
    op.create_index("ix_user_flex_gifts_recipient_id", "user_flex_gifts", ["recipient_id"])
    op.create_index("ix_user_flex_gifts_status", "user_flex_gifts", ["status"])
    op.create_index("ix_user_flex_gifts_payment_id", "user_flex_gifts", ["payment_id"])


def downgrade() -> None:
    if not _table_exists("user_flex_gifts"):
        return
    op.drop_index("ix_user_flex_gifts_payment_id", table_name="user_flex_gifts")
    op.drop_index("ix_user_flex_gifts_status", table_name="user_flex_gifts")
    op.drop_index("ix_user_flex_gifts_recipient_id", table_name="user_flex_gifts")
    op.drop_index("ix_user_flex_gifts_sender_id", table_name="user_flex_gifts")
    op.drop_table("user_flex_gifts")
