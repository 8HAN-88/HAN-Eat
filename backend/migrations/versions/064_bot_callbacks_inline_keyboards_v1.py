"""bot callbacks and inline keyboards v1

Revision ID: 064_bot_callbacks_inline_keyboards_v1
Revises: 063_miniapps_moderation_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "064_bot_callbacks_inline_keyboards_v1"
down_revision = "063_miniapps_moderation_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "messages",
        sa.Column("inline_keyboard_json", sa.String(length=4000), nullable=True),
    )
    op.add_column(
        "bot_commands",
        sa.Column("response_text", sa.String(length=2000), nullable=True),
    )
    op.add_column(
        "bot_commands",
        sa.Column("inline_buttons_json", sa.String(length=4000), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("bot_commands", "inline_buttons_json")
    op.drop_column("bot_commands", "response_text")
    op.drop_column("messages", "inline_keyboard_json")
