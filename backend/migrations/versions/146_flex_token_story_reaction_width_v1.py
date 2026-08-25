"""Widen story reaction emoji for ce:{id} tokens.

Revision ID: 146_flex_token_story_reaction_width_v1
Revises: 145_flex_token_emoji_width_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "146_flex_token_story_reaction_width_v1"
down_revision = "145_flex_token_emoji_width_v1"
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
    if _table_exists("story_reactions") and "emoji" in _columns("story_reactions"):
        op.alter_column(
            "story_reactions",
            "emoji",
            existing_type=sa.String(length=16),
            type_=sa.String(length=32),
            existing_nullable=False,
        )


def downgrade() -> None:
    if _table_exists("story_reactions") and "emoji" in _columns("story_reactions"):
        op.alter_column(
            "story_reactions",
            "emoji",
            existing_type=sa.String(length=32),
            type_=sa.String(length=16),
            existing_nullable=False,
        )
