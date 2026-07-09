"""group member admin roles

Revision ID: 071_group_member_admin_roles_v1
Revises: 070_group_posting_restrictions_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "071_group_member_admin_roles_v1"
down_revision = "070_group_posting_restrictions_v1"
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
    if not _table_exists("conversation_members"):
        return
    if not _column_exists("conversation_members", "is_admin"):
        op.add_column(
            "conversation_members",
            sa.Column("is_admin", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        )


def downgrade() -> None:
    # Keep downgrade conservative to avoid destructive rollback on production data.
    pass
