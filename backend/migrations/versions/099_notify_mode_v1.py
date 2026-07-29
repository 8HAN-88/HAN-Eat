"""conversation_members.notify_mode for mute mention control

Revision ID: 099_notify_mode_v1
Revises: 098_sticker_favorites_pins_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "099_notify_mode_v1"
down_revision = "098_sticker_favorites_pins_v1"
branch_labels = None
depends_on = None


def _columns(table: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return {c["name"] for c in inspector.get_columns(table)}


def upgrade() -> None:
    cols = _columns("conversation_members")
    if "notify_mode" not in cols:
        op.add_column(
            "conversation_members",
            sa.Column(
                "notify_mode",
                sa.String(length=16),
                nullable=False,
                server_default="all",
            ),
        )
        # Existing mutes behave as Telegram default: mentions still notify.
        op.execute(
            """
            UPDATE conversation_members
            SET notify_mode = 'mentions'
            WHERE muted_at IS NOT NULL
            """
        )


def downgrade() -> None:
    cols = _columns("conversation_members")
    if "notify_mode" in cols:
        op.drop_column("conversation_members", "notify_mode")
