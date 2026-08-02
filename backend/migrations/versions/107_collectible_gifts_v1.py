"""Telegram-like collectible Star gifts + transfer metadata

Revision ID: 107_collectible_gifts_v1
Revises: 106_star_giveaways_invoices_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "107_collectible_gifts_v1"
down_revision = "106_star_giveaways_invoices_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "star_gifts",
        sa.Column("is_limited", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.add_column(
        "star_gifts",
        sa.Column("total_supply", sa.Integer(), nullable=True),
    )
    op.add_column(
        "star_gifts",
        sa.Column("sold_count", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "star_gifts",
        sa.Column("upgrade_stars", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "star_gifts",
        sa.Column("transfer_stars", sa.Integer(), nullable=False, server_default="0"),
    )
    op.create_index("ix_star_gifts_is_limited", "star_gifts", ["is_limited"])

    op.add_column(
        "user_star_gifts",
        sa.Column("is_collectible", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.add_column(
        "user_star_gifts",
        sa.Column("serial", sa.Integer(), nullable=True),
    )
    op.add_column(
        "user_star_gifts",
        sa.Column(
            "transferred_from_user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )
    op.create_index("ix_user_star_gifts_is_collectible", "user_star_gifts", ["is_collectible"])
    op.create_index("ix_user_star_gifts_serial", "user_star_gifts", ["serial"])
    op.create_index(
        "ix_user_star_gifts_transferred_from_user_id",
        "user_star_gifts",
        ["transferred_from_user_id"],
    )
    # NULL serials (non-collectibles) are allowed multiple times in PG/SQLite UNIQUE.
    op.create_index(
        "uq_user_star_gifts_gift_serial",
        "user_star_gifts",
        ["gift_id", "serial"],
        unique=True,
    )

    # Seed a couple of limited collectibles + upgrade paths on premium gifts.
    op.execute(
        """
        UPDATE star_gifts
        SET upgrade_stars = 75, transfer_stars = 15
        WHERE slug IN ('diamond', 'trophy')
        """
    )
    gifts = sa.table(
        "star_gifts",
        sa.column("slug", sa.String),
        sa.column("title", sa.String),
        sa.column("emoji", sa.String),
        sa.column("stars", sa.Integer),
        sa.column("is_active", sa.Boolean),
        sa.column("sort_order", sa.Integer),
        sa.column("is_limited", sa.Boolean),
        sa.column("total_supply", sa.Integer),
        sa.column("sold_count", sa.Integer),
        sa.column("upgrade_stars", sa.Integer),
        sa.column("transfer_stars", sa.Integer),
    )
    op.bulk_insert(
        gifts,
        [
            {
                "slug": "lonestar",
                "title": "Одинокая звезда",
                "emoji": "🌟",
                "stars": 100,
                "is_active": True,
                "sort_order": 70,
                "is_limited": True,
                "total_supply": 1000,
                "sold_count": 0,
                "upgrade_stars": 0,
                "transfer_stars": 25,
            },
            {
                "slug": "phoenix",
                "title": "Феникс",
                "emoji": "🔥",
                "stars": 250,
                "is_active": True,
                "sort_order": 80,
                "is_limited": True,
                "total_supply": 500,
                "sold_count": 0,
                "upgrade_stars": 0,
                "transfer_stars": 50,
            },
        ],
    )


def downgrade() -> None:
    op.execute("DELETE FROM star_gifts WHERE slug IN ('lonestar', 'phoenix')")
    op.drop_index("uq_user_star_gifts_gift_serial", table_name="user_star_gifts")
    op.drop_index(
        "ix_user_star_gifts_transferred_from_user_id", table_name="user_star_gifts"
    )
    op.drop_index("ix_user_star_gifts_serial", table_name="user_star_gifts")
    op.drop_index("ix_user_star_gifts_is_collectible", table_name="user_star_gifts")
    op.drop_column("user_star_gifts", "transferred_from_user_id")
    op.drop_column("user_star_gifts", "serial")
    op.drop_column("user_star_gifts", "is_collectible")

    op.drop_index("ix_star_gifts_is_limited", table_name="star_gifts")
    op.drop_column("star_gifts", "transfer_stars")
    op.drop_column("star_gifts", "upgrade_stars")
    op.drop_column("star_gifts", "sold_count")
    op.drop_column("star_gifts", "total_supply")
    op.drop_column("star_gifts", "is_limited")
