"""Recipe & channel visibility modes (public/private/mixed)

Revision ID: 034_recipe_visibility_v1
Revises: 033_meal_plan_cooldown_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "034_recipe_visibility_v1"
down_revision = "033_meal_plan_cooldown_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "channels",
        sa.Column(
            "recipe_visibility_mode",
            sa.String(length=20),
            nullable=False,
            server_default="mixed",
        ),
    )
    op.add_column(
        "posts",
        sa.Column(
            "is_global_visible",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
        ),
    )
    op.add_column(
        "posts",
        sa.Column(
            "is_indexed",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
        ),
    )
    op.create_index("ix_posts_is_global_visible", "posts", ["is_global_visible"])
    op.create_index("ix_posts_is_indexed", "posts", ["is_indexed"])

    # Профильные рецепты: public → глобально; канальные — только public
    op.execute(
        """
        UPDATE posts SET
            is_global_visible = (
                type = 'recipe'
                AND status = 'published'
                AND deleted_at IS NULL
                AND COALESCE(visibility, 'public') = 'public'
                AND COALESCE(hidden_from_recommendations, false) = false
            ),
            is_indexed = (
                type = 'recipe'
                AND status = 'published'
                AND deleted_at IS NULL
                AND COALESCE(visibility, 'public') = 'public'
                AND COALESCE(hidden_from_recommendations, false) = false
            )
        """
    )
    # Канальные рецепты по умолчанию не в глобальном Menu (до явного public)
    op.execute(
        """
        UPDATE posts SET is_global_visible = false, is_indexed = false
        WHERE channel_id IS NOT NULL AND type = 'recipe'
        """
    )


def downgrade() -> None:
    op.drop_index("ix_posts_is_indexed", table_name="posts")
    op.drop_index("ix_posts_is_global_visible", table_name="posts")
    op.drop_column("posts", "is_indexed")
    op.drop_column("posts", "is_global_visible")
    op.drop_column("channels", "recipe_visibility_mode")
