"""Disable archived kitchen builtin mini-apps

Revision ID: 102_disable_builtin_miniapps_v1
Revises: 101_miniapp_category_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "102_disable_builtin_miniapps_v1"
down_revision = "101_miniapp_category_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    tables = set(inspector.get_table_names())
    if "bot_miniapps" not in tables:
        return
    cols = {c["name"] for c in inspector.get_columns("bot_miniapps")}
    if "is_builtin" not in cols or "is_active" not in cols:
        return
    op.execute(
        sa.text(
            "UPDATE bot_miniapps "
            "SET is_active = false "
            "WHERE is_builtin = true"
        )
    )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    tables = set(inspector.get_table_names())
    if "bot_miniapps" not in tables:
        return
    cols = {c["name"] for c in inspector.get_columns("bot_miniapps")}
    if "is_builtin" not in cols or "is_active" not in cols:
        return
    op.execute(
        sa.text(
            "UPDATE bot_miniapps "
            "SET is_active = true "
            "WHERE is_builtin = true"
        )
    )
