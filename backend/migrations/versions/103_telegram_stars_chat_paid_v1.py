"""Telegram Stars chat paid features: paid media, gifts, paid DMs, paid reactions

Revision ID: 103_telegram_stars_chat_paid_v1
Revises: 102_disable_builtin_miniapps_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "103_telegram_stars_chat_paid_v1"
down_revision = "102_disable_builtin_miniapps_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("paid_message_stars", sa.Integer(), nullable=False, server_default="0"),
    )

    op.add_column(
        "messages",
        sa.Column("is_paid", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.add_column(
        "messages",
        sa.Column("price_stars", sa.Integer(), nullable=False, server_default="0"),
    )
    op.create_index("ix_messages_is_paid", "messages", ["is_paid"])

    op.add_column(
        "message_reactions",
        sa.Column("stars_amount", sa.Integer(), nullable=False, server_default="0"),
    )

    op.create_table(
        "paid_message_unlocks",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("message_id", sa.Integer(), sa.ForeignKey("messages.id", ondelete="CASCADE"), nullable=False),
        sa.Column("author_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("amount_stars", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(24), nullable=False, server_default="completed"),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("user_id", "message_id", name="uq_paid_message_unlock_user_msg"),
    )
    op.create_index("ix_paid_message_unlocks_user_id", "paid_message_unlocks", ["user_id"])
    op.create_index("ix_paid_message_unlocks_message_id", "paid_message_unlocks", ["message_id"])
    op.create_index("ix_paid_message_unlocks_author_id", "paid_message_unlocks", ["author_id"])
    op.create_index("ix_paid_message_unlocks_status", "paid_message_unlocks", ["status"])
    op.create_index("ix_paid_message_unlocks_created_at", "paid_message_unlocks", ["created_at"])

    op.create_table(
        "star_gifts",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("slug", sa.String(64), nullable=False),
        sa.Column("title", sa.String(120), nullable=False),
        sa.Column("emoji", sa.String(16), nullable=False, server_default="🎁"),
        sa.Column("stars", sa.Integer(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("slug", name="uq_star_gifts_slug"),
    )
    op.create_index("ix_star_gifts_is_active", "star_gifts", ["is_active"])
    op.create_index("ix_star_gifts_sort_order", "star_gifts", ["sort_order"])

    gifts = sa.table(
        "star_gifts",
        sa.column("slug", sa.String),
        sa.column("title", sa.String),
        sa.column("emoji", sa.String),
        sa.column("stars", sa.Integer),
        sa.column("is_active", sa.Boolean),
        sa.column("sort_order", sa.Integer),
    )
    op.bulk_insert(
        gifts,
        [
            {"slug": "star", "title": "Звезда", "emoji": "⭐", "stars": 15, "is_active": True, "sort_order": 10},
            {"slug": "rose", "title": "Роза", "emoji": "🌹", "stars": 25, "is_active": True, "sort_order": 20},
            {"slug": "cake", "title": "Торт", "emoji": "🎂", "stars": 50, "is_active": True, "sort_order": 30},
            {"slug": "gift", "title": "Подарок", "emoji": "🎁", "stars": 100, "is_active": True, "sort_order": 40},
            {"slug": "diamond", "title": "Бриллиант", "emoji": "💎", "stars": 250, "is_active": True, "sort_order": 50},
            {"slug": "trophy", "title": "Кубок", "emoji": "🏆", "stars": 500, "is_active": True, "sort_order": 60},
        ],
    )


def downgrade() -> None:
    op.drop_index("ix_star_gifts_sort_order", table_name="star_gifts")
    op.drop_index("ix_star_gifts_is_active", table_name="star_gifts")
    op.drop_table("star_gifts")

    op.drop_index("ix_paid_message_unlocks_created_at", table_name="paid_message_unlocks")
    op.drop_index("ix_paid_message_unlocks_status", table_name="paid_message_unlocks")
    op.drop_index("ix_paid_message_unlocks_author_id", table_name="paid_message_unlocks")
    op.drop_index("ix_paid_message_unlocks_message_id", table_name="paid_message_unlocks")
    op.drop_index("ix_paid_message_unlocks_user_id", table_name="paid_message_unlocks")
    op.drop_table("paid_message_unlocks")

    op.drop_column("message_reactions", "stars_amount")
    op.drop_index("ix_messages_is_paid", table_name="messages")
    op.drop_column("messages", "price_stars")
    op.drop_column("messages", "is_paid")
    op.drop_column("users", "paid_message_stars")
