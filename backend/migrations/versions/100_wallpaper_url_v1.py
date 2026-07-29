"""conversation_members.wallpaper_url for custom wallpaper cloud sync

Revision ID: 100_wallpaper_url_v1
Revises: 099_notify_mode_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "100_wallpaper_url_v1"
down_revision = "099_notify_mode_v1"
branch_labels = None
depends_on = None


def _columns(table: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return {c["name"] for c in inspector.get_columns(table)}


def upgrade() -> None:
    cols = _columns("conversation_members")
    if "wallpaper_url" not in cols:
        op.add_column(
            "conversation_members",
            sa.Column("wallpaper_url", sa.String(length=512), nullable=True),
        )


def downgrade() -> None:
    cols = _columns("conversation_members")
    if "wallpaper_url" in cols:
        op.drop_column("conversation_members", "wallpaper_url")
