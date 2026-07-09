"""group member send restrictions

Revision ID: 073_group_member_send_restrictions_v1
Revises: 072_group_moderator_permissions_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "073_group_member_send_restrictions_v1"
down_revision = "072_group_moderator_permissions_v1"
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


def _add_column_if_missing(table_name: str, column: sa.Column) -> None:
    if not _column_exists(table_name, column.name):
        op.add_column(table_name, column)


def upgrade() -> None:
    if not _table_exists("conversation_members"):
        return
    _add_column_if_missing(
        "conversation_members",
        sa.Column(
            "send_restricted",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )
    _add_column_if_missing(
        "conversation_members",
        sa.Column("send_restricted_until", sa.DateTime(), nullable=True),
    )
    _add_column_if_missing(
        "conversation_members",
        sa.Column("send_restriction_reason", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    # Keep downgrade conservative to avoid destructive rollback on production data.
    pass
