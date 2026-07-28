"""scheduled_messages.silent + disable_webpage_preview

Revision ID: 096_scheduled_silent_disable_preview_v1
Revises: 095_bubble_accent_disable_preview_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "096_scheduled_silent_disable_preview_v1"
down_revision = "095_bubble_accent_disable_preview_v1"
branch_labels = None
depends_on = None


def _columns(table: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return {c["name"] for c in inspector.get_columns(table)}


def upgrade() -> None:
    cols = _columns("scheduled_messages")
    if "silent" not in cols:
        op.add_column(
            "scheduled_messages",
            sa.Column(
                "silent",
                sa.Boolean(),
                nullable=False,
                server_default=sa.false(),
            ),
        )
    if "disable_webpage_preview" not in cols:
        op.add_column(
            "scheduled_messages",
            sa.Column(
                "disable_webpage_preview",
                sa.Boolean(),
                nullable=False,
                server_default=sa.false(),
            ),
        )


def downgrade() -> None:
    cols = _columns("scheduled_messages")
    if "disable_webpage_preview" in cols:
        op.drop_column("scheduled_messages", "disable_webpage_preview")
    if "silent" in cols:
        op.drop_column("scheduled_messages", "silent")
