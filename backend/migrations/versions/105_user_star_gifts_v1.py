"""Telegram-like user star gift inventory (hold / convert / display)

Revision ID: 105_user_star_gifts_v1
Revises: 104_paid_message_exceptions_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "105_user_star_gifts_v1"
down_revision = "104_paid_message_exceptions_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "user_star_gifts",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "owner_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "sender_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "gift_id",
            sa.Integer(),
            sa.ForeignKey("star_gifts.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "message_id",
            sa.Integer(),
            sa.ForeignKey("messages.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("stars", sa.Integer(), nullable=False),
        sa.Column("slug", sa.String(64), nullable=False, server_default="gift"),
        sa.Column("title", sa.String(120), nullable=False, server_default="Подарок"),
        sa.Column("emoji", sa.String(16), nullable=False, server_default="🎁"),
        sa.Column("note", sa.String(500), nullable=True),
        sa.Column("status", sa.String(24), nullable=False, server_default="held"),
        sa.Column("is_displayed", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("converted_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_user_star_gifts_owner_id", "user_star_gifts", ["owner_id"])
    op.create_index("ix_user_star_gifts_sender_id", "user_star_gifts", ["sender_id"])
    op.create_index("ix_user_star_gifts_gift_id", "user_star_gifts", ["gift_id"])
    op.create_index("ix_user_star_gifts_message_id", "user_star_gifts", ["message_id"])
    op.create_index("ix_user_star_gifts_status", "user_star_gifts", ["status"])
    op.create_index("ix_user_star_gifts_is_displayed", "user_star_gifts", ["is_displayed"])
    op.create_index("ix_user_star_gifts_created_at", "user_star_gifts", ["created_at"])


def downgrade() -> None:
    op.drop_index("ix_user_star_gifts_created_at", table_name="user_star_gifts")
    op.drop_index("ix_user_star_gifts_is_displayed", table_name="user_star_gifts")
    op.drop_index("ix_user_star_gifts_status", table_name="user_star_gifts")
    op.drop_index("ix_user_star_gifts_message_id", table_name="user_star_gifts")
    op.drop_index("ix_user_star_gifts_gift_id", table_name="user_star_gifts")
    op.drop_index("ix_user_star_gifts_sender_id", table_name="user_star_gifts")
    op.drop_index("ix_user_star_gifts_owner_id", table_name="user_star_gifts")
    op.drop_table("user_star_gifts")
