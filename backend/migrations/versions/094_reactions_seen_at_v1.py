"""conversation_members.reactions_seen_at for unread reaction badges

Revision ID: 094_reactions_seen_at_v1
Revises: 093_wallpaper_style_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "094_reactions_seen_at_v1"
down_revision = "093_wallpaper_style_v1"
branch_labels = None
depends_on = None


def _columns(table: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return {c["name"] for c in inspector.get_columns(table)}


def upgrade() -> None:
    cols = _columns("conversation_members")
    if "reactions_seen_at" not in cols:
        op.add_column(
            "conversation_members",
            sa.Column("reactions_seen_at", sa.DateTime(), nullable=True),
        )


def downgrade() -> None:
    cols = _columns("conversation_members")
    if "reactions_seen_at" in cols:
        op.drop_column("conversation_members", "reactions_seen_at")
