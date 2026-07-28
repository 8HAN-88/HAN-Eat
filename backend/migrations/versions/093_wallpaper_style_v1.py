"""conversation_members.wallpaper_style for cloud wallpaper sync

Revision ID: 093_wallpaper_style_v1
Revises: 092_muted_until_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "093_wallpaper_style_v1"
down_revision = "092_muted_until_v1"
branch_labels = None
depends_on = None


def _columns(table: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return {c["name"] for c in inspector.get_columns(table)}


def upgrade() -> None:
    cols = _columns("conversation_members")
    if "wallpaper_style" not in cols:
        op.add_column(
            "conversation_members",
            sa.Column("wallpaper_style", sa.String(length=32), nullable=True),
        )


def downgrade() -> None:
    cols = _columns("conversation_members")
    if "wallpaper_style" in cols:
        op.drop_column("conversation_members", "wallpaper_style")
