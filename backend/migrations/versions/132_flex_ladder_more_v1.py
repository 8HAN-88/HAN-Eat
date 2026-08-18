"""Append flex rungs 17–20 (scheduled, wallpaper, stories).

Revision ID: 132_flex_ladder_more_v1
Revises: 131_flex_ladder_stretch_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "132_flex_ladder_more_v1"
down_revision = "131_flex_ladder_stretch_v1"
branch_labels = None
depends_on = None

_BLOCK = {
    "key": "E",
    "title": "Ещё",
    "min_level": 17,
    "max_level": 20,
    "sort_order": 5,
}

_FEATURES = (
    {
        "slug": "scheduled_messages",
        "title": "Отложенные сообщения",
        "description": "Отправка в чат по расписанию или когда собеседник будет в сети.",
        "icon": "schedule_send",
        "default_level": 17,
    },
    {
        "slug": "chat_wallpaper",
        "title": "Обои и оформление чата",
        "description": "Свои фото-обои и пресеты Сумерки, Лес, Песок, Ночь.",
        "icon": "wallpaper",
        "default_level": 18,
    },
    {
        "slug": "story_viewers",
        "title": "Кто смотрел сторис",
        "description": "Список просмотров ваших сторис.",
        "icon": "visibility",
        "default_level": 19,
    },
    {
        "slug": "story_close_friends",
        "title": "Сторис для близких",
        "description": "Публикация сторис только для списка близких.",
        "icon": "favorite",
        "default_level": 20,
    },
)


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def upgrade() -> None:
    bind = op.get_bind()
    if not _table_exists("subscription_feature_blocks"):
        return
    blocks = sa.table(
        "subscription_feature_blocks",
        sa.column("key", sa.String),
        sa.column("title", sa.String),
        sa.column("min_level", sa.Integer),
        sa.column("max_level", sa.Integer),
        sa.column("sort_order", sa.Integer),
    )
    existing_keys = {
        row[0] for row in bind.execute(sa.text("SELECT key FROM subscription_feature_blocks"))
    }
    if "E" not in existing_keys:
        bind.execute(blocks.insert().values(**_BLOCK))

    if not _table_exists("subscription_features"):
        return
    features = sa.table(
        "subscription_features",
        sa.column("slug", sa.String),
        sa.column("title", sa.String),
        sa.column("description", sa.Text),
        sa.column("icon", sa.String),
        sa.column("min_level", sa.Integer),
        sa.column("max_level", sa.Integer),
        sa.column("default_level", sa.Integer),
        sa.column("feature_type", sa.String),
        sa.column("movable", sa.Boolean),
        sa.column("required", sa.Boolean),
        sa.column("block_key", sa.String),
        sa.column("status", sa.String),
        sa.column("available", sa.Boolean),
        sa.column("sort_order", sa.Integer),
    )
    existing_slugs = {
        row[0] for row in bind.execute(sa.text("SELECT slug FROM subscription_features"))
    }
    next_order = bind.execute(
        sa.text("SELECT COALESCE(MAX(sort_order), 0) FROM subscription_features")
    ).scalar() or 0
    for spec in _FEATURES:
        if spec["slug"] in existing_slugs:
            continue
        next_order += 1
        bind.execute(
            features.insert().values(
                slug=spec["slug"],
                title=spec["title"],
                description=spec["description"],
                icon=spec["icon"],
                min_level=17,
                max_level=20,
                default_level=spec["default_level"],
                feature_type="blocked",
                movable=True,
                required=False,
                block_key="E",
                status="active",
                available=True,
                sort_order=next_order,
            )
        )


def downgrade() -> None:
    bind = op.get_bind()
    if _table_exists("subscription_features"):
        slugs = ", ".join(f"'{row['slug']}'" for row in _FEATURES)
        bind.execute(
            sa.text(f"DELETE FROM subscription_features WHERE slug IN ({slugs})")
        )
    if _table_exists("subscription_feature_blocks"):
        bind.execute(sa.text("DELETE FROM subscription_feature_blocks WHERE key = 'E'"))
