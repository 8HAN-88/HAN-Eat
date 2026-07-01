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


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def _column_exists(table_name: str, column_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if table_name not in inspector.get_table_names():
        return False
    return any(col.get("name") == column_name for col in inspector.get_columns(table_name))


def upgrade() -> None:
    if _table_exists("messages") and not _column_exists("messages", "inline_keyboard_json"):
        op.add_column(
            "messages",
            sa.Column("inline_keyboard_json", sa.String(length=4000), nullable=True),
        )

    if not _table_exists("bot_commands"):
        op.create_table(
            "bot_commands",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("bot_id", sa.Integer(), nullable=False),
            sa.Column("command", sa.String(length=32), nullable=False),
            sa.Column("description", sa.String(length=256), nullable=False),
            sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=True),
            sa.ForeignKeyConstraint(["bot_id"], ["users.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
        )
        op.create_index("ix_bot_commands_id", "bot_commands", ["id"], unique=False)
        op.create_index("ix_bot_commands_bot_id", "bot_commands", ["bot_id"], unique=False)

    if not _column_exists("bot_commands", "response_text"):
        op.add_column(
            "bot_commands",
            sa.Column("response_text", sa.String(length=2000), nullable=True),
        )
    if not _column_exists("bot_commands", "inline_buttons_json"):
        op.add_column(
            "bot_commands",
            sa.Column("inline_buttons_json", sa.String(length=4000), nullable=True),
        )


def downgrade() -> None:
    if _column_exists("bot_commands", "inline_buttons_json"):
        op.drop_column("bot_commands", "inline_buttons_json")
    if _column_exists("bot_commands", "response_text"):
        op.drop_column("bot_commands", "response_text")
    if _column_exists("messages", "inline_keyboard_json"):
        op.drop_column("messages", "inline_keyboard_json")
