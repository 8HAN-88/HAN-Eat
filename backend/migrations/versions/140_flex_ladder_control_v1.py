"""Append flex rungs 49–52 and last_read_at.

Revision ID: 140_flex_ladder_control_v1
Revises: 139_flex_ladder_live_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "140_flex_ladder_control_v1"
down_revision = "139_flex_ladder_live_v1"
branch_labels = None
depends_on = None

_BLOCK = {
    "key": "M",
    "title": "Контроль",
    "min_level": 49,
    "max_level": 52,
    "sort_order": 13,
}

_FEATURES = (
    {
        "slug": "default_folder",
        "title": "Папка при запуске",
        "description": "Сразу открывать выбранную папку вместо общего списка чатов.",
        "icon": "folder_special",
        "default_level": 49,
    },
    {
        "slug": "hide_forward",
        "title": "Пересылка без автора",
        "description": "Переслать сообщение как копию — без подписи «Переслано от…».",
        "icon": "content_copy",
        "default_level": 50,
    },
    {
        "slug": "read_timestamps",
        "title": "Время прочтения",
        "description": "Точное время, когда собеседник прочитал ваши сообщения.",
        "icon": "schedule",
        "default_level": 51,
    },
    {
        "slug": "edit_history",
        "title": "История правок",
        "description": "Посмотреть предыдущие версии изменённого сообщения.",
        "icon": "history",
        "default_level": 52,
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
    member_cols = _columns("conversation_members")
    if "last_read_at" not in member_cols and _table_exists("conversation_members"):
        op.add_column(
            "conversation_members",
            sa.Column("last_read_at", sa.DateTime(), nullable=True),
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
    if "M" not in existing_keys:
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
                min_level=49,
                max_level=52,
                default_level=spec["default_level"],
                feature_type="blocked",
                movable=True,
                required=False,
                block_key="M",
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
        bind.execute(sa.text("DELETE FROM subscription_feature_blocks WHERE key = 'M'"))
    if "last_read_at" in _columns("conversation_members"):
        op.drop_column("conversation_members", "last_read_at")
