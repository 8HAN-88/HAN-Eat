"""Anonymous Star gifts (Telegram hide-my-name)

Revision ID: 123_anonymous_star_gifts_v1
Revises: 122_message_is_anonymous_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "123_anonymous_star_gifts_v1"
down_revision = "122_message_is_anonymous_v1"
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
    return any(c["name"] == column_name for c in inspector.get_columns(table_name))


def upgrade() -> None:
    if not _table_exists("user_star_gifts"):
        return
    if not _column_exists("user_star_gifts", "is_anonymous"):
        op.add_column(
            "user_star_gifts",
            sa.Column(
                "is_anonymous",
                sa.Boolean(),
                nullable=False,
                server_default="false",
            ),
        )
        op.create_index(
            "ix_user_star_gifts_is_anonymous",
            "user_star_gifts",
            ["is_anonymous"],
        )


def downgrade() -> None:
    if not _table_exists("user_star_gifts"):
        return
    if _column_exists("user_star_gifts", "is_anonymous"):
        op.drop_index("ix_user_star_gifts_is_anonymous", table_name="user_star_gifts")
        op.drop_column("user_star_gifts", "is_anonymous")
