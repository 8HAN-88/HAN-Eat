"""group invite links

Revision ID: 075_group_invite_links_v1
Revises: 074_group_member_ban_list_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "075_group_invite_links_v1"
down_revision = "074_group_member_ban_list_v1"
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
    if not _table_exists("conversations"):
        return
    if not _column_exists("conversations", "invite_token"):
        op.add_column(
            "conversations",
            sa.Column("invite_token", sa.String(length=96), nullable=True),
        )
    if not _column_exists("conversations", "invite_token_updated_at"):
        op.add_column(
            "conversations",
            sa.Column("invite_token_updated_at", sa.DateTime(), nullable=True),
        )
    if not _index_exists("conversations", "ix_conversations_invite_token"):
        op.create_index(
            "ix_conversations_invite_token",
            "conversations",
            ["invite_token"],
            unique=True,
        )


def downgrade() -> None:
    # Keep downgrade conservative to avoid destructive rollback on production data.
    pass
