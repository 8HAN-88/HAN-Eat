"""Append flex rungs 25–28 (silent, search, quizzes, video notes).

Revision ID: 134_flex_ladder_chat_v1
Revises: 133_flex_ladder_media_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "134_flex_ladder_chat_v1"
down_revision = "133_flex_ladder_media_v1"
branch_labels = None
depends_on = None

_BLOCK = {
    "key": "G",
    "title": "Чат+",
    "min_level": 25,
    "max_level": 28,
    "sort_order": 7,
}

_FEATURES = (
    {
        "slug": "silent_send",
        "title": "Отправка без звука",
        "description": "Сообщение доставляется без push-уведомления.",
        "icon": "notifications_off",
        "default_level": 25,
    },
    {
        "slug": "chat_search",
        "title": "Поиск по сообщениям",
        "description": "Поиск по тексту, дате и типу сообщений во всех чатах.",
        "icon": "search",
        "default_level": 26,
    },
    {
        "slug": "poll_quiz",
        "title": "Викторины и опросы+",
        "description": "Викторина, несколько ответов, таймер и скрытые результаты.",
        "icon": "quiz",
        "default_level": 27,
    },
    {
        "slug": "video_notes",
        "title": "Видеосообщения",
        "description": "Кружочки — короткие круглые видео в чате.",
        "icon": "videocam",
        "default_level": 28,
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
    if "G" not in existing_keys:
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
                min_level=25,
                max_level=28,
                default_level=spec["default_level"],
                feature_type="blocked",
                movable=True,
                required=False,
                block_key="G",
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
        bind.execute(sa.text("DELETE FROM subscription_feature_blocks WHERE key = 'G'"))
