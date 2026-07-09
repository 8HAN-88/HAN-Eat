"""scheduled messages online delivery columns

Revision ID: 069_scheduled_messages_online_delivery_v1
Revises: 068_scheduled_chat_messages_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "069_scheduled_messages_online_delivery_v1"
down_revision = "068_scheduled_chat_messages_v1"
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
    if not _table_exists("scheduled_messages"):
        return

    if not _column_exists("scheduled_messages", "deliver_when_online"):
        op.add_column(
            "scheduled_messages",
            sa.Column("deliver_when_online", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        )
    if not _column_exists("scheduled_messages", "target_user_id"):
        op.add_column(
            "scheduled_messages",
            sa.Column("target_user_id", sa.Integer(), nullable=True),
        )
        op.create_foreign_key(
            "fk_scheduled_messages_target_user_id_users",
            "scheduled_messages",
            "users",
            ["target_user_id"],
            ["id"],
            ondelete="SET NULL",
        )
    if not _index_exists("scheduled_messages", "ix_scheduled_messages_target_user_id"):
        op.create_index(
            "ix_scheduled_messages_target_user_id",
            "scheduled_messages",
            ["target_user_id"],
            unique=False,
        )


def downgrade() -> None:
    # Keep downgrade conservative to avoid destructive rollback on production data.
    pass
