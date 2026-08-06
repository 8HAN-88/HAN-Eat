"""User TOTP two-factor auth

Revision ID: 115_user_totp_2fa_v1
Revises: 114_auth_sessions_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "115_user_totp_2fa_v1"
down_revision = "114_auth_sessions_v1"
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
    if not _column_exists("users", "totp_secret"):
        op.add_column("users", sa.Column("totp_secret", sa.String(length=64), nullable=True))
    if not _column_exists("users", "totp_enabled"):
        op.add_column(
            "users",
            sa.Column(
                "totp_enabled",
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("false"),
            ),
        )
    if not _column_exists("users", "totp_enabled_at"):
        op.add_column("users", sa.Column("totp_enabled_at", sa.DateTime(), nullable=True))


def downgrade() -> None:
    pass
