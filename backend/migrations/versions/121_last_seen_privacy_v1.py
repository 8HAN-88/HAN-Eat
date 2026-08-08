"""User last_seen_privacy tiers (everybody/contacts/nobody)

Revision ID: 121_last_seen_privacy_v1
Revises: 120_scheduled_effect_topic_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "121_last_seen_privacy_v1"
down_revision = "120_scheduled_effect_topic_v1"
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
    if not _table_exists("users"):
        return
    if not _column_exists("users", "last_seen_privacy"):
        op.add_column(
            "users",
            sa.Column(
                "last_seen_privacy",
                sa.String(length=20),
                nullable=False,
                server_default="everybody",
            ),
        )
    # Backfill from legacy show_last_seen when present.
    if _column_exists("users", "show_last_seen"):
        op.execute(
            sa.text(
                "UPDATE users SET last_seen_privacy = 'nobody' "
                "WHERE show_last_seen = false OR show_last_seen = 0"
            )
        )
        op.execute(
            sa.text(
                "UPDATE users SET last_seen_privacy = 'everybody' "
                "WHERE show_last_seen = true OR show_last_seen = 1"
            )
        )


def downgrade() -> None:
    if not _table_exists("users"):
        return
    if _column_exists("users", "last_seen_privacy"):
        op.drop_column("users", "last_seen_privacy")
