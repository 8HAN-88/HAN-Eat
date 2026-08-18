"""Append flex rungs 29–32 (protect, channel search, smart folders).

Revision ID: 135_flex_ladder_tg_v1
Revises: 134_flex_ladder_chat_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "135_flex_ladder_tg_v1"
down_revision = "134_flex_ladder_chat_v1"
branch_labels = None
depends_on = None

_BLOCK = {
    "key": "H",
    "title": "Telegram+",
    "min_level": 29,
    "max_level": 32,
    "sort_order": 8,
}

_FEATURES = (
    {
        "slug": "no_forwards",
        "title": "Запрет пересылки",
        "description": "Защита контента группы: нельзя пересылать и сохранять сообщения.",
        "icon": "lock",
        "default_level": 29,
    },
    {
        "slug": "channel_post_search",
        "title": "Поиск по каналу",
        "description": "Поиск постов внутри канала по тексту, тегам и рецепту.",
        "icon": "travel_explore",
        "default_level": 30,
    },
    {
        "slug": "folder_filters",
        "title": "Умные папки",
        "description": "Автосбор папки: контакты, боты, непрочитанные, без архива.",
        "icon": "filter_alt",
        "default_level": 31,
    },
    {
        "slug": "folder_icons",
        "title": "Эмодзи папок",
        "description": "Своя иконка-эмодзи у папки чатов, как в Telegram Premium.",
        "icon": "emoji_emotions",
        "default_level": 32,
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
    if "H" not in existing_keys:
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
                min_level=29,
                max_level=32,
                default_level=spec["default_level"],
                feature_type="blocked",
                movable=True,
                required=False,
                block_key="H",
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
        bind.execute(sa.text("DELETE FROM subscription_feature_blocks WHERE key = 'H'"))
