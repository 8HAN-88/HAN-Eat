"""group slow mode and antiflood

Revision ID: 079_group_slow_mode_antiflood_v1
Revises: 078_group_invite_links_backfill_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "079_group_slow_mode_antiflood_v1"
down_revision = "078_group_invite_links_backfill_v1"
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
    if _table_exists("conversations"):
        _add_column_if_missing(
            "conversations",
            sa.Column(
                "slow_mode_seconds",
                sa.Integer(),
                nullable=False,
                server_default=sa.text("0"),
            ),
        )
        _add_column_if_missing(
            "conversations",
            sa.Column(
                "anti_flood_max_messages_per_minute",
                sa.Integer(),
                nullable=False,
                server_default=sa.text("0"),
            ),
        )
    if _table_exists("conversation_members"):
        _add_column_if_missing(
            "conversation_members",
            sa.Column("last_group_message_at", sa.DateTime(), nullable=True),
        )


def downgrade() -> None:
    # Keep downgrade conservative to avoid destructive rollback on production data.
    pass
