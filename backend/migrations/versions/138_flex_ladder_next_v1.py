"""Append flex rungs 41–44 and story/call/sticker columns.

Revision ID: 138_flex_ladder_next_v1
Revises: 137_flex_ladder_plus_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "138_flex_ladder_next_v1"
down_revision = "137_flex_ladder_plus_v1"
branch_labels = None
depends_on = None

_BLOCK = {
    "key": "K",
    "title": "Сторис+",
    "min_level": 41,
    "max_level": 44,
    "sort_order": 11,
}

_FEATURES = (
    {
        "slug": "story_stealth",
        "title": "Скрытый просмотр",
        "description": "Смотреть сторис, не попадая в список просмотров.",
        "icon": "visibility_off",
        "default_level": 41,
    },
    {
        "slug": "longer_stories",
        "title": "Длинные сторис",
        "description": "Видео до 60 секунд и сторис на 48 часов, как в Telegram Premium.",
        "icon": "timelapse",
        "default_level": 42,
    },
    {
        "slug": "premium_stickers",
        "title": "Премиум-стикеры",
        "description": "Ставить и отправлять эксклюзивные стикерпаки.",
        "icon": "auto_awesome",
        "default_level": 43,
    },
    {
        "slug": "call_privacy",
        "title": "Кто звонит",
        "description": "Ограничить входящие звонки: все, контакты или никто.",
        "icon": "phone_disabled",
        "default_level": 44,
    },
)


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def _columns(table_name: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if table_name not in inspector.get_table_names():
        return set()
    return {col["name"] for col in inspector.get_columns(table_name)}


def upgrade() -> None:
    bind = op.get_bind()
    user_cols = _columns("users")
    if "story_stealth" not in user_cols and _table_exists("users"):
        op.add_column(
            "users",
            sa.Column(
                "story_stealth",
                sa.Boolean(),
                nullable=False,
                server_default=sa.false(),
            ),
        )
    if "call_privacy" not in user_cols and _table_exists("users"):
        op.add_column(
            "users",
            sa.Column(
                "call_privacy",
                sa.String(20),
                nullable=False,
                server_default="everybody",
            ),
        )
    pack_cols = _columns("sticker_packs")
    if "is_premium" not in pack_cols and _table_exists("sticker_packs"):
        op.add_column(
            "sticker_packs",
            sa.Column(
                "is_premium",
                sa.Boolean(),
                nullable=False,
                server_default=sa.false(),
            ),
        )

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
    if "K" not in existing_keys:
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
                min_level=41,
                max_level=44,
                default_level=spec["default_level"],
                feature_type="blocked",
                movable=True,
                required=False,
                block_key="K",
                status="active",
                available=True,
                sort_order=next_order,
            )
        )


def downgrade() -> None:
    bind = op.get_bind()
    if _table_exists("subscription_features"):
        slugs = ", ".join(f"'{row['slug']}'" for row in _FEATURES)
        bind.execute(sa.text(f"DELETE FROM subscription_features WHERE slug IN ({slugs})"))
    if _table_exists("subscription_feature_blocks"):
        bind.execute(sa.text("DELETE FROM subscription_feature_blocks WHERE key = 'K'"))
    if "is_premium" in _columns("sticker_packs"):
        op.drop_column("sticker_packs", "is_premium")
    if "call_privacy" in _columns("users"):
        op.drop_column("users", "call_privacy")
    if "story_stealth" in _columns("users"):
        op.drop_column("users", "story_stealth")
