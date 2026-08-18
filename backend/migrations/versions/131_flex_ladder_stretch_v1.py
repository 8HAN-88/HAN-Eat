"""Append messenger+ rungs 11–16 to the flex catalog.

Revision ID: 131_flex_ladder_stretch_v1
Revises: 130_flex_gifts_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "131_flex_ladder_stretch_v1"
down_revision = "130_flex_gifts_v1"
branch_labels = None
depends_on = None

_BLOCK = {
    "key": "D",
    "title": "Мессенджер+",
    "min_level": 11,
    "max_level": 16,
    "sort_order": 4,
}

_FEATURES = (
    {
        "slug": "chat_translation",
        "title": "Перевод сообщений",
        "description": "Перевод текста в чатах на нужный язык.",
        "icon": "translate",
        "default_level": 11,
    },
    {
        "slug": "extra_pins",
        "title": "Больше закрепов",
        "description": "До 20 закреплённых сообщений в чате вместо пяти.",
        "icon": "push_pin",
        "default_level": 12,
    },
    {
        "slug": "larger_uploads",
        "title": "Большие файлы",
        "description": "Фото до 50 МБ, документы до 100 МБ, аудио до 20 МБ.",
        "icon": "upload_file",
        "default_level": 13,
    },
    {
        "slug": "privacy_plus",
        "title": "Приватность last seen",
        "description": "Скрывайте свой статус и всё равно видите, кто в сети.",
        "icon": "visibility_off",
        "default_level": 14,
    },
    {
        "slug": "extra_folders",
        "title": "Больше папок",
        "description": "До 50 папок чатов вместо десяти.",
        "icon": "folder",
        "default_level": 15,
    },
    {
        "slug": "message_effects",
        "title": "Эффекты сообщений",
        "description": "Конфетти, фейерверк и праздник при отправке.",
        "icon": "celebration",
        "default_level": 16,
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
    if "D" not in existing_keys:
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
                min_level=11,
                max_level=16,
                default_level=spec["default_level"],
                feature_type="blocked",
                movable=True,
                required=False,
                block_key="D",
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
        bind.execute(sa.text("DELETE FROM subscription_feature_blocks WHERE key = 'D'"))
