"""Bot ReplyKeyboard on members + commands

Revision ID: 117_bot_reply_keyboard_v1
Revises: 116_close_friends_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "117_bot_reply_keyboard_v1"
down_revision = "116_close_friends_v1"
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
    if _table_exists("conversation_members"):
        if not _column_exists("conversation_members", "reply_keyboard_json"):
            op.add_column(
                "conversation_members",
                sa.Column("reply_keyboard_json", sa.String(length=4000), nullable=True),
            )
        if not _column_exists("conversation_members", "reply_keyboard_one_time"):
            op.add_column(
                "conversation_members",
                sa.Column(
                    "reply_keyboard_one_time",
                    sa.Boolean(),
                    nullable=False,
                    server_default=sa.text("false"),
                ),
            )
        if not _column_exists("conversation_members", "reply_keyboard_resize"):
            op.add_column(
                "conversation_members",
                sa.Column(
                    "reply_keyboard_resize",
                    sa.Boolean(),
                    nullable=False,
                    server_default=sa.text("true"),
                ),
            )
        if not _column_exists("conversation_members", "reply_keyboard_placeholder"):
            op.add_column(
                "conversation_members",
                sa.Column("reply_keyboard_placeholder", sa.String(length=64), nullable=True),
            )

    if _table_exists("bot_commands"):
        if not _column_exists("bot_commands", "reply_buttons_json"):
            op.add_column(
                "bot_commands",
                sa.Column("reply_buttons_json", sa.String(length=4000), nullable=True),
            )
        if not _column_exists("bot_commands", "reply_keyboard_one_time"):
            op.add_column(
                "bot_commands",
                sa.Column(
                    "reply_keyboard_one_time",
                    sa.Boolean(),
                    nullable=False,
                    server_default=sa.text("false"),
                ),
            )
        if not _column_exists("bot_commands", "reply_keyboard_resize"):
            op.add_column(
                "bot_commands",
                sa.Column(
                    "reply_keyboard_resize",
                    sa.Boolean(),
                    nullable=False,
                    server_default=sa.text("true"),
                ),
            )
        if not _column_exists("bot_commands", "reply_keyboard_placeholder"):
            op.add_column(
                "bot_commands",
                sa.Column("reply_keyboard_placeholder", sa.String(length=64), nullable=True),
            )
        if not _column_exists("bot_commands", "remove_reply_keyboard"):
            op.add_column(
                "bot_commands",
                sa.Column(
                    "remove_reply_keyboard",
                    sa.Boolean(),
                    nullable=False,
                    server_default=sa.text("false"),
                ),
            )


def downgrade() -> None:
    pass
