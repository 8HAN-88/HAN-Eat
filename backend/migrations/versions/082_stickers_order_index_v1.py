"""add order index for sticker sorting

Revision ID: 082_stickers_order_index_v1
Revises: 081_stickers_animated_type_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "082_stickers_order_index_v1"
down_revision = "081_stickers_animated_type_v1"
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
    if _table_exists("stickers") and not _column_exists("stickers", "order_index"):
        op.add_column(
            "stickers",
            sa.Column(
                "order_index",
                sa.Integer(),
                nullable=False,
                server_default=sa.text("0"),
            ),
        )
        op.create_index("ix_stickers_order_index", "stickers", ["order_index"], unique=False)


def downgrade() -> None:
    # conservative downgrade
    pass
