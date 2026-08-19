"""Append flex rungs 37–40 and privacy/saved-tag columns.

Revision ID: 137_flex_ladder_plus_v1
Revises: 136_flex_ladder_premium_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "137_flex_ladder_plus_v1"
down_revision = "136_flex_ladder_premium_v1"
branch_labels = None
depends_on = None

_BLOCK = {
    "key": "J",
    "title": "Ещё+",
    "min_level": 37,
    "max_level": 40,
    "sort_order": 10,
}

_FEATURES = (
    {
        "slug": "any_emoji_reactions",
        "title": "Любые реакции",
        "description": "Реакция любым эмодзи, не только из короткой панели.",
        "icon": "emoji_emotions",
        "default_level": 37,
    },
    {
        "slug": "voice_privacy",
        "title": "Кто шлёт голос",
        "description": "Ограничить голосовые и кружки: все, контакты или никто.",
        "icon": "mic_off",
        "default_level": 38,
    },
    {
        "slug": "saved_tags",
        "title": "Теги в Избранном",
        "description": "Метки для сообщений в Избранном, как в Telegram Premium.",
        "icon": "sell",
        "default_level": 39,
    },
    {
        "slug": "archive_non_contacts",
        "title": "Архив незнакомцев",
        "description": "Новые чаты не из контактов сразу в архив и без звука.",
        "icon": "inventory_2",
        "default_level": 40,
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
    if "voice_privacy" not in user_cols and _table_exists("users"):
        op.add_column(
            "users",
            sa.Column("voice_privacy", sa.String(20), nullable=False, server_default="everybody"),
        )
    if "archive_non_contacts" not in user_cols and _table_exists("users"):
        op.add_column(
            "users",
            sa.Column(
                "archive_non_contacts",
                sa.Boolean(),
                nullable=False,
                server_default=sa.false(),
            ),
        )
    if "default_folder_id" not in user_cols and _table_exists("users"):
        op.add_column("users", sa.Column("default_folder_id", sa.Integer(), nullable=True))

    if not _table_exists("saved_tags"):
        op.create_table(
            "saved_tags",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("title", sa.String(40), nullable=False),
            sa.Column("emoji", sa.String(8), nullable=True),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
        )
        op.create_index("ix_saved_tags_user_id", "saved_tags", ["user_id"])
    if not _table_exists("saved_message_tags"):
        op.create_table(
            "saved_message_tags",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "tag_id",
                sa.Integer(),
                sa.ForeignKey("saved_tags.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "message_id",
                sa.Integer(),
                sa.ForeignKey("messages.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.UniqueConstraint("tag_id", "message_id", name="uq_saved_tag_message"),
        )
        op.create_index("ix_saved_message_tags_tag_id", "saved_message_tags", ["tag_id"])
        op.create_index("ix_saved_message_tags_message_id", "saved_message_tags", ["message_id"])

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
    if "J" not in existing_keys:
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
                min_level=37,
                max_level=40,
                default_level=spec["default_level"],
                feature_type="blocked",
                movable=True,
                required=False,
                block_key="J",
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
        bind.execute(sa.text("DELETE FROM subscription_feature_blocks WHERE key = 'J'"))
    if _table_exists("saved_message_tags"):
        op.drop_table("saved_message_tags")
    if _table_exists("saved_tags"):
        op.drop_table("saved_tags")
    if "default_folder_id" in _columns("users"):
        op.drop_column("users", "default_folder_id")
    if "archive_non_contacts" in _columns("users"):
        op.drop_column("users", "archive_non_contacts")
    if "voice_privacy" in _columns("users"):
        op.drop_column("users", "voice_privacy")
