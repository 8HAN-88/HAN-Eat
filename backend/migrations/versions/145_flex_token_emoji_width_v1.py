"""Widen sticker emoji and topic icon for [[e:id]] tokens.

Revision ID: 145_flex_token_emoji_width_v1
Revises: 144_flex_token_icon_width_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "145_flex_token_emoji_width_v1"
down_revision = "144_flex_token_icon_width_v1"
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    inspector = sa.inspect(op.get_bind())
    return table_name in inspector.get_table_names()


def _columns(table_name: str) -> set[str]:
    inspector = sa.inspect(op.get_bind())
    if table_name not in inspector.get_table_names():
        return set()
    return {col["name"] for col in inspector.get_columns(table_name)}


def upgrade() -> None:
    if _table_exists("stickers") and "emoji" in _columns("stickers"):
        op.alter_column(
            "stickers",
            "emoji",
            existing_type=sa.String(length=16),
            type_=sa.String(length=32),
            existing_nullable=True,
        )
    if _table_exists("forum_topics") and "icon_emoji" in _columns("forum_topics"):
        op.alter_column(
            "forum_topics",
            "icon_emoji",
            existing_type=sa.String(length=16),
            type_=sa.String(length=32),
            existing_nullable=True,
        )


def downgrade() -> None:
    if _table_exists("forum_topics") and "icon_emoji" in _columns("forum_topics"):
        op.alter_column(
            "forum_topics",
            "icon_emoji",
            existing_type=sa.String(length=32),
            type_=sa.String(length=16),
            existing_nullable=True,
        )
    if _table_exists("stickers") and "emoji" in _columns("stickers"):
        op.alter_column(
            "stickers",
            "emoji",
            existing_type=sa.String(length=32),
            type_=sa.String(length=16),
            existing_nullable=True,
        )
