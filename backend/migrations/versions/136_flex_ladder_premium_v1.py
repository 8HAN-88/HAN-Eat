"""Append flex rungs 33–36 and profile/voice premium columns.

Revision ID: 136_flex_ladder_premium_v1
Revises: 135_flex_ladder_tg_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "136_flex_ladder_premium_v1"
down_revision = "135_flex_ladder_tg_v1"
branch_labels = None
depends_on = None

_BLOCK = {
    "key": "I",
    "title": "Премиум",
    "min_level": 33,
    "max_level": 36,
    "sort_order": 9,
}

_FEATURES = (
    {
        "slug": "voice_to_text",
        "title": "Голос в текст",
        "description": "Расшифровка голосовых и кружков, как в Telegram Premium.",
        "icon": "hearing",
        "default_level": 33,
    },
    {
        "slug": "emoji_status",
        "title": "Emoji-статус",
        "description": "Эмодзи рядом с именем в чатах и профиле.",
        "icon": "mood",
        "default_level": 34,
    },
    {
        "slug": "checklist",
        "title": "Чеклисты",
        "description": "Списки дел в чате: пункты можно отмечать вместе.",
        "icon": "checklist",
        "default_level": 35,
    },
    {
        "slug": "profile_colors",
        "title": "Цвет профиля",
        "description": "Цвет имени в списке чатов и в профиле.",
        "icon": "palette",
        "default_level": 36,
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
    if "emoji_status" not in user_cols and _table_exists("users"):
        op.add_column("users", sa.Column("emoji_status", sa.String(16), nullable=True))
    if "profile_color" not in user_cols and _table_exists("users"):
        op.add_column("users", sa.Column("profile_color", sa.String(16), nullable=True))
    msg_cols = _columns("messages")
    if "transcription" not in msg_cols and _table_exists("messages"):
        op.add_column("messages", sa.Column("transcription", sa.Text(), nullable=True))

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
    if "I" not in existing_keys:
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
                min_level=33,
                max_level=36,
                default_level=spec["default_level"],
                feature_type="blocked",
                movable=True,
                required=False,
                block_key="I",
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
        bind.execute(sa.text("DELETE FROM subscription_feature_blocks WHERE key = 'I'"))
    if "transcription" in _columns("messages"):
        op.drop_column("messages", "transcription")
    if "profile_color" in _columns("users"):
        op.drop_column("users", "profile_color")
    if "emoji_status" in _columns("users"):
        op.drop_column("users", "emoji_status")
