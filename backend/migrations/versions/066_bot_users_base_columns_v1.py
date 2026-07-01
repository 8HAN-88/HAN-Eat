"""ensure base bot columns on users

Revision ID: 066_bot_users_base_v1
Revises: 065_bot_webhook_fields_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "066_bot_users_base_v1"
down_revision = "065_bot_webhook_fields_v1"
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


def _index_exists(table_name: str, index_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if table_name not in inspector.get_table_names():
        return False
    return any(idx.get("name") == index_name for idx in inspector.get_indexes(table_name))


def upgrade() -> None:
    if not _table_exists("users"):
        return

    if not _column_exists("users", "is_bot"):
        op.add_column("users", sa.Column("is_bot", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    if not _column_exists("users", "bot_token"):
        op.add_column("users", sa.Column("bot_token", sa.String(length=64), nullable=True))
    if not _column_exists("users", "bot_username"):
        op.add_column("users", sa.Column("bot_username", sa.String(length=32), nullable=True))
    if not _column_exists("users", "bot_description"):
        op.add_column("users", sa.Column("bot_description", sa.Text(), nullable=True))
    if not _column_exists("users", "bot_short_description"):
        op.add_column("users", sa.Column("bot_short_description", sa.String(length=120), nullable=True))
    if not _column_exists("users", "bot_avatar_url"):
        op.add_column("users", sa.Column("bot_avatar_url", sa.Text(), nullable=True))
    if not _column_exists("users", "created_by_user_id"):
        op.add_column("users", sa.Column("created_by_user_id", sa.Integer(), nullable=True))

    op.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_users_bot_token "
        "ON users(bot_token) WHERE bot_token IS NOT NULL"
    )
    op.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_users_bot_username "
        "ON users(bot_username) WHERE bot_username IS NOT NULL"
    )

    if not _index_exists("users", "ix_users_bot_token"):
        op.create_index("ix_users_bot_token", "users", ["bot_token"], unique=False)
    if not _index_exists("users", "ix_users_bot_username"):
        op.create_index("ix_users_bot_username", "users", ["bot_username"], unique=False)

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
            sa.UniqueConstraint("bot_id", "command", name="uq_bot_commands_bot_command"),
        )
        op.create_index("ix_bot_commands_id", "bot_commands", ["id"], unique=False)
        op.create_index("ix_bot_commands_bot_id", "bot_commands", ["bot_id"], unique=False)


def downgrade() -> None:
    # Keep downgrade conservative to avoid destructive rollback on production data.
    pass

