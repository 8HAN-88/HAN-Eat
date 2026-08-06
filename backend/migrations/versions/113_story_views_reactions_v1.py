"""Story viewers list + emoji reactions

Revision ID: 113_story_views_reactions_v1
Revises: 112_message_has_spoiler_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "113_story_views_reactions_v1"
down_revision = "112_message_has_spoiler_v1"
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def upgrade() -> None:
    if not _table_exists("stories"):
        return

    if not _table_exists("story_views"):
        op.create_table(
            "story_views",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "story_id",
                sa.Integer(),
                sa.ForeignKey("stories.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "viewed_at",
                sa.DateTime(),
                server_default=sa.text("CURRENT_TIMESTAMP"),
                nullable=False,
            ),
            sa.UniqueConstraint("story_id", "user_id", name="uq_story_view_user"),
        )
        op.create_index("ix_story_views_story_id", "story_views", ["story_id"])
        op.create_index("ix_story_views_user_id", "story_views", ["user_id"])

    if not _table_exists("story_reactions"):
        op.create_table(
            "story_reactions",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "story_id",
                sa.Integer(),
                sa.ForeignKey("stories.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("emoji", sa.String(length=16), nullable=False),
            sa.Column(
                "created_at",
                sa.DateTime(),
                server_default=sa.text("CURRENT_TIMESTAMP"),
                nullable=False,
            ),
            sa.UniqueConstraint("story_id", "user_id", name="uq_story_reaction_user"),
        )
        op.create_index("ix_story_reactions_story_id", "story_reactions", ["story_id"])
        op.create_index("ix_story_reactions_user_id", "story_reactions", ["user_id"])


def downgrade() -> None:
    if _table_exists("story_reactions"):
        op.drop_index("ix_story_reactions_user_id", table_name="story_reactions")
        op.drop_index("ix_story_reactions_story_id", table_name="story_reactions")
        op.drop_table("story_reactions")
    if _table_exists("story_views"):
        op.drop_index("ix_story_views_user_id", table_name="story_views")
        op.drop_index("ix_story_views_story_id", table_name="story_views")
        op.drop_table("story_views")
