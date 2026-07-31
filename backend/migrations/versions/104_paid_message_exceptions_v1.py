"""Paid DM exceptions: users who can message without Stars fee

Revision ID: 104_paid_message_exceptions_v1
Revises: 103_telegram_stars_chat_paid_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "104_paid_message_exceptions_v1"
down_revision = "103_telegram_stars_chat_paid_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "paid_message_exceptions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("owner_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("allowed_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.UniqueConstraint("owner_id", "allowed_user_id", name="uq_paid_message_exception_pair"),
    )
    op.create_index(
        "ix_paid_message_exceptions_owner_id",
        "paid_message_exceptions",
        ["owner_id"],
    )
    op.create_index(
        "ix_paid_message_exceptions_allowed_user_id",
        "paid_message_exceptions",
        ["allowed_user_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_paid_message_exceptions_allowed_user_id", table_name="paid_message_exceptions")
    op.drop_index("ix_paid_message_exceptions_owner_id", table_name="paid_message_exceptions")
    op.drop_table("paid_message_exceptions")
