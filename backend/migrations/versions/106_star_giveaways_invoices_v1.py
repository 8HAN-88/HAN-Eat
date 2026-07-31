"""Telegram-like Star giveaways and bot Stars invoices

Revision ID: 106_star_giveaways_invoices_v1
Revises: 105_user_star_gifts_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "106_star_giveaways_invoices_v1"
down_revision = "105_user_star_gifts_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "star_giveaways",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "channel_id",
            sa.Integer(),
            sa.ForeignKey("channels.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "creator_user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("prize_stars", sa.Integer(), nullable=False),
        sa.Column("winners_count", sa.Integer(), nullable=False),
        sa.Column("total_escrow_stars", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(24), nullable=False, server_default="active"),
        sa.Column("ends_at", sa.DateTime(), nullable=False),
        sa.Column("require_membership", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("participants_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("title", sa.String(160), nullable=True),
        sa.Column("completed_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_star_giveaways_channel_id", "star_giveaways", ["channel_id"])
    op.create_index("ix_star_giveaways_creator_user_id", "star_giveaways", ["creator_user_id"])
    op.create_index("ix_star_giveaways_status", "star_giveaways", ["status"])
    op.create_index("ix_star_giveaways_ends_at", "star_giveaways", ["ends_at"])
    op.create_index("ix_star_giveaways_created_at", "star_giveaways", ["created_at"])

    op.create_table(
        "star_giveaway_participants",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "giveaway_id",
            sa.Integer(),
            sa.ForeignKey("star_giveaways.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("is_winner", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint(
            "giveaway_id", "user_id", name="uq_star_giveaway_participant"
        ),
    )
    op.create_index(
        "ix_star_giveaway_participants_giveaway_id",
        "star_giveaway_participants",
        ["giveaway_id"],
    )
    op.create_index(
        "ix_star_giveaway_participants_user_id",
        "star_giveaway_participants",
        ["user_id"],
    )
    op.create_index(
        "ix_star_giveaway_participants_is_winner",
        "star_giveaway_participants",
        ["is_winner"],
    )

    op.create_table(
        "star_invoices",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "bot_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "creator_user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "payer_user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("title", sa.String(160), nullable=False),
        sa.Column("description", sa.String(512), nullable=True),
        sa.Column("amount_stars", sa.Integer(), nullable=False),
        sa.Column("payload", sa.String(256), nullable=True),
        sa.Column("status", sa.String(24), nullable=False, server_default="pending"),
        sa.Column("expires_at", sa.DateTime(), nullable=True),
        sa.Column("paid_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_star_invoices_bot_id", "star_invoices", ["bot_id"])
    op.create_index("ix_star_invoices_creator_user_id", "star_invoices", ["creator_user_id"])
    op.create_index("ix_star_invoices_payer_user_id", "star_invoices", ["payer_user_id"])
    op.create_index("ix_star_invoices_status", "star_invoices", ["status"])
    op.create_index("ix_star_invoices_created_at", "star_invoices", ["created_at"])


def downgrade() -> None:
    op.drop_index("ix_star_invoices_created_at", table_name="star_invoices")
    op.drop_index("ix_star_invoices_status", table_name="star_invoices")
    op.drop_index("ix_star_invoices_payer_user_id", table_name="star_invoices")
    op.drop_index("ix_star_invoices_creator_user_id", table_name="star_invoices")
    op.drop_index("ix_star_invoices_bot_id", table_name="star_invoices")
    op.drop_table("star_invoices")

    op.drop_index("ix_star_giveaway_participants_is_winner", table_name="star_giveaway_participants")
    op.drop_index("ix_star_giveaway_participants_user_id", table_name="star_giveaway_participants")
    op.drop_index(
        "ix_star_giveaway_participants_giveaway_id", table_name="star_giveaway_participants"
    )
    op.drop_table("star_giveaway_participants")

    op.drop_index("ix_star_giveaways_created_at", table_name="star_giveaways")
    op.drop_index("ix_star_giveaways_ends_at", table_name="star_giveaways")
    op.drop_index("ix_star_giveaways_status", table_name="star_giveaways")
    op.drop_index("ix_star_giveaways_creator_user_id", table_name="star_giveaways")
    op.drop_index("ix_star_giveaways_channel_id", table_name="star_giveaways")
    op.drop_table("star_giveaways")
