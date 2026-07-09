"""group join requests

Revision ID: 076_group_join_requests_v1
Revises: 075_group_invite_links_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "076_group_join_requests_v1"
down_revision = "075_group_invite_links_v1"
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
    if _table_exists("conversations") and not _column_exists(
        "conversations", "join_by_request_enabled"
    ):
        op.add_column(
            "conversations",
            sa.Column(
                "join_by_request_enabled",
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("false"),
            ),
        )

    if not _table_exists("group_join_requests"):
        op.create_table(
            "group_join_requests",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("conversation_id", sa.Integer(), nullable=False),
            sa.Column("user_id", sa.Integer(), nullable=False),
            sa.Column(
                "status",
                sa.String(length=20),
                nullable=False,
                server_default=sa.text("'pending'"),
            ),
            sa.Column(
                "requested_at",
                sa.DateTime(),
                nullable=True,
                server_default=sa.text("CURRENT_TIMESTAMP"),
            ),
            sa.Column("reviewed_at", sa.DateTime(), nullable=True),
            sa.Column("reviewed_by_user_id", sa.Integer(), nullable=True),
            sa.ForeignKeyConstraint(["conversation_id"], ["conversations.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["reviewed_by_user_id"], ["users.id"], ondelete="SET NULL"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("conversation_id", "user_id", name="uq_group_join_request_pair"),
        )
    if not _index_exists("group_join_requests", "ix_group_join_requests_conversation_id"):
        op.create_index(
            "ix_group_join_requests_conversation_id",
            "group_join_requests",
            ["conversation_id"],
            unique=False,
        )
    if not _index_exists("group_join_requests", "ix_group_join_requests_user_id"):
        op.create_index(
            "ix_group_join_requests_user_id",
            "group_join_requests",
            ["user_id"],
            unique=False,
        )
    if not _index_exists("group_join_requests", "ix_group_join_requests_status"):
        op.create_index(
            "ix_group_join_requests_status",
            "group_join_requests",
            ["status"],
            unique=False,
        )


def downgrade() -> None:
    # Keep downgrade conservative to avoid destructive rollback on production data.
    pass
