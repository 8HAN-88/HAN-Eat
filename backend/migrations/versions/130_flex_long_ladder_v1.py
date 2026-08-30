"""Expand Flex catalog to an 18-step one-feature ladder.

Revision ID: 130_flex_long_ladder_v1
Revises: 129_post_reactions_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "130_flex_long_ladder_v1"
down_revision = "129_post_reactions_v1"
branch_labels = None
depends_on = None


_FEATURE_PLACEMENT = (
    ("ad_free", 1, 1, 1, "A", "fixed", False, True),
    ("premium_badge", 2, 1, 6, "A", "movable", True, False),
    ("exclusive_reactions", 3, 1, 6, "A", "movable", True, False),
    ("larger_uploads", 4, 1, 6, "A", "movable", True, False),
    ("profile_decoration", 5, 1, 6, "A", "movable", True, False),
    ("priority_reels_quality", 6, 1, 6, "A", "movable", True, False),
    ("ai_recommendations", 7, 7, 9, "B", "blocked", True, False),
    ("ai_priority_speed", 8, 7, 9, "B", "blocked", True, False),
    ("offline_saved_posts", 9, 7, 9, "B", "blocked", True, False),
    ("creator_tools", 10, 10, 16, "C", "premium", True, False),
    ("creator_badge", 11, 10, 16, "C", "blocked", True, False),
    ("creator_scheduled_posts", 12, 10, 16, "C", "blocked", True, False),
    ("creator_promotion", 13, 10, 16, "C", "blocked", True, False),
    ("creator_pinned", 14, 10, 16, "C", "blocked", True, False),
    ("creator_analytics", 15, 10, 16, "C", "blocked", True, False),
    ("advanced_stats", 16, 10, 16, "C", "blocked", True, False),
    ("priority_support", 17, 17, 17, "C", "fixed", False, True),
    ("pro", 18, 18, 18, "C", "fixed", False, True),
)

_COMPACT_CASE = """
CASE {column}
    WHEN 1 THEN 1
    WHEN 2 THEN 4
    WHEN 3 THEN 6
    WHEN 4 THEN 7
    WHEN 5 THEN 8
    WHEN 6 THEN 9
    WHEN 7 THEN 11
    WHEN 8 THEN 14
    WHEN 9 THEN 16
    WHEN 10 THEN 18
    ELSE {column}
END
"""


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    tables = set(inspector.get_table_names())
    if "subscription_feature_blocks" not in tables:
        return

    compact = bind.execute(
        sa.text("SELECT COALESCE(MAX(default_level), 0) FROM subscription_features")
    ).scalar()
    is_compact = int(compact or 0) <= 10

    bind.execute(
        sa.text(
            "UPDATE subscription_feature_blocks "
            "SET title = 'Базовые функции', min_level = 1, max_level = 6, sort_order = 1 "
            "WHERE key = 'A'"
        )
    )
    bind.execute(
        sa.text(
            "UPDATE subscription_feature_blocks "
            "SET title = 'Расширенные функции', min_level = 7, max_level = 9, sort_order = 2 "
            "WHERE key = 'B'"
        )
    )
    bind.execute(
        sa.text(
            "UPDATE subscription_feature_blocks "
            "SET title = 'PRO', min_level = 10, max_level = 18, sort_order = 3 "
            "WHERE key = 'C'"
        )
    )

    for index, (slug, default, min_level, max_level, block, ftype, movable, required) in enumerate(
        _FEATURE_PLACEMENT, start=1
    ):
        bind.execute(
            sa.text(
                "UPDATE subscription_features SET "
                "default_level = :default_level, min_level = :min_level, "
                "max_level = :max_level, block_key = :block_key, "
                "feature_type = :feature_type, movable = :movable, "
                "required = :required, sort_order = :sort_order "
                "WHERE slug = :slug"
            ),
            {
                "default_level": default,
                "min_level": min_level,
                "max_level": max_level,
                "block_key": block,
                "feature_type": ftype,
                "movable": movable,
                "required": required,
                "sort_order": index,
                "slug": slug,
            },
        )

    if is_compact and "user_flex_subscriptions" in tables:
        bind.execute(
            sa.text(
                "UPDATE user_flex_subscriptions SET current_level = "
                + _COMPACT_CASE.format(column="current_level")
                + " WHERE current_level BETWEEN 1 AND 10"
            )
        )
    if is_compact and "user_flex_slots" in tables:
        bind.execute(
            sa.text(
                "UPDATE user_flex_slots SET assigned_level = "
                + _COMPACT_CASE.format(column="assigned_level")
                + " WHERE assigned_level BETWEEN 1 AND 10"
            )
        )
        bind.execute(
            sa.text(
                "UPDATE user_flex_slots AS slots SET assigned_level = "
                "GREATEST(features.min_level, LEAST(features.max_level, slots.assigned_level)) "
                "FROM subscription_features AS features "
                "WHERE features.id = slots.feature_id"
            )
        )


def downgrade() -> None:
    return
