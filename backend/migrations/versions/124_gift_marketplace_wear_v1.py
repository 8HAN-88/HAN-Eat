"""Collectible gift resale marketplace + wear on profile.

Revision ID: 124_gift_marketplace_wear_v1
Revises: 125_paid_refunds_suggested_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "124_gift_marketplace_wear_v1"
down_revision = "125_paid_refunds_suggested_v1"
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
    if not _table_exists("user_star_gifts"):
        return
    if not _column_exists("user_star_gifts", "listed_stars"):
        op.add_column(
            "user_star_gifts",
            sa.Column("listed_stars", sa.Integer(), nullable=True),
        )
        op.create_index(
            "ix_user_star_gifts_listed_stars",
            "user_star_gifts",
            ["listed_stars"],
        )
    if not _column_exists("user_star_gifts", "listed_at"):
        op.add_column(
            "user_star_gifts",
            sa.Column("listed_at", sa.DateTime(), nullable=True),
        )
    if not _column_exists("user_star_gifts", "is_worn"):
        op.add_column(
            "user_star_gifts",
            sa.Column(
                "is_worn",
                sa.Boolean(),
                nullable=False,
                server_default="false",
            ),
        )
        op.create_index(
            "ix_user_star_gifts_is_worn",
            "user_star_gifts",
            ["is_worn"],
        )


def downgrade() -> None:
    if not _table_exists("user_star_gifts"):
        return
    if _column_exists("user_star_gifts", "is_worn"):
        op.drop_index("ix_user_star_gifts_is_worn", table_name="user_star_gifts")
        op.drop_column("user_star_gifts", "is_worn")
    if _column_exists("user_star_gifts", "listed_at"):
        op.drop_column("user_star_gifts", "listed_at")
    if _column_exists("user_star_gifts", "listed_stars"):
        op.drop_index("ix_user_star_gifts_listed_stars", table_name="user_star_gifts")
        op.drop_column("user_star_gifts", "listed_stars")
