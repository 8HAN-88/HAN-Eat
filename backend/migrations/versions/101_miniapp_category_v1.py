"""bot_miniapps.category for food-native discovery

Revision ID: 101_miniapp_category_v1
Revises: 100_wallpaper_url_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "101_miniapp_category_v1"
down_revision = "100_wallpaper_url_v1"
branch_labels = None
depends_on = None


def _columns(table: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return {c["name"] for c in inspector.get_columns(table)}


def upgrade() -> None:
    cols = _columns("bot_miniapps")
    if "category" not in cols:
        op.add_column(
            "bot_miniapps",
            sa.Column("category", sa.String(length=32), nullable=True),
        )


def downgrade() -> None:
    cols = _columns("bot_miniapps")
    if "category" in cols:
        op.drop_column("bot_miniapps", "category")
