"""Emoji reactions on feed and channel posts.

Revision ID: 129_post_reactions_v1
Revises: 128_flex_multi_features_level_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "129_post_reactions_v1"
down_revision = "128_flex_multi_features_level_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "post_reactions" in inspector.get_table_names():
        return
    op.create_table(
        "post_reactions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("post_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("emoji", sa.String(length=16), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
        sa.UniqueConstraint("post_id", "user_id", name="uq_post_reaction_user"),
    )
    op.create_index("ix_post_reactions_post_id", "post_reactions", ["post_id"])
    op.create_index("ix_post_reactions_user_id", "post_reactions", ["user_id"])


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "post_reactions" not in inspector.get_table_names():
        return
    op.drop_index("ix_post_reactions_user_id", table_name="post_reactions")
    op.drop_index("ix_post_reactions_post_id", table_name="post_reactions")
    op.drop_table("post_reactions")
