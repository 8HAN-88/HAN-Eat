"""Anonymous admin flag on messages

Revision ID: 122_message_is_anonymous_v1
Revises: 121_last_seen_privacy_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "122_message_is_anonymous_v1"
down_revision = "121_last_seen_privacy_v1"
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
    if _table_exists("messages") and not _column_exists("messages", "is_anonymous"):
        op.add_column(
            "messages",
            sa.Column(
                "is_anonymous",
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("false"),
            ),
        )


def downgrade() -> None:
    if _table_exists("messages") and _column_exists("messages", "is_anonymous"):
        op.drop_column("messages", "is_anonymous")
