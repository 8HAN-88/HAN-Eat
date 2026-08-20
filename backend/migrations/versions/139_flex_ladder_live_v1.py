"""Append flex rungs 45–48 and inbox/story columns.

Revision ID: 139_flex_ladder_live_v1
Revises: 138_flex_ladder_next_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "139_flex_ladder_live_v1"
down_revision = "138_flex_ladder_next_v1"
branch_labels = None
depends_on = None

_BLOCK = {
    "key": "L",
    "title": "Входящие+",
    "min_level": 45,
    "max_level": 48,
    "sort_order": 12,
}

_FEATURES = (
    {
        "slug": "extra_pinned_chats",
        "title": "Больше закрепов в ленте",
        "description": "До 20 закреплённых чатов во входящих вместо пяти.",
        "icon": "push_pin",
        "default_level": 45,
    },
    {
        "slug": "story_download",
        "title": "Сохранить сторис",
        "description": "Скачать сторис в галерею, как в Telegram Premium.",
        "icon": "download",
        "default_level": 46,
    },
    {
        "slug": "auto_translate",
        "title": "Автоперевод чата",
        "description": "Сразу переводить входящие сообщения в выбранном чате.",
        "icon": "translate",
        "default_level": 47,
    },
    {
        "slug": "chat_tags",
        "title": "Метки чатов",
        "description": "Цветные метки на чатах и фильтр входящих, как в Telegram Premium.",
        "icon": "label",
        "default_level": 48,
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
    if "auto_translate" not in member_cols and _table_exists("conversation_members"):
        op.add_column(
            "conversation_members",
            sa.Column(
                "auto_translate",
                sa.Boolean(),
                nullable=False,
                server_default=sa.false(),
            ),
        )

    if not _table_exists("chat_tags"):
        op.create_table(
            "chat_tags",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("title", sa.String(40), nullable=False),
            sa.Column("color", sa.String(16), nullable=False, server_default="blue"),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        )
        op.create_index("ix_chat_tags_user_id", "chat_tags", ["user_id"])
    if not _table_exists("conversation_chat_tags"):
        op.create_table(
            "conversation_chat_tags",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column(
                "conversation_id",
                sa.Integer(),
                sa.ForeignKey("conversations.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "tag_id",
                sa.Integer(),
                sa.ForeignKey("chat_tags.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.UniqueConstraint(
                "user_id",
                "conversation_id",
                "tag_id",
                name="uq_conversation_chat_tag",
            ),
        )
        op.create_index("ix_conversation_chat_tags_user_id", "conversation_chat_tags", ["user_id"])
        op.create_index(
            "ix_conversation_chat_tags_conversation_id",
            "conversation_chat_tags",
            ["conversation_id"],
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
    if "L" not in existing_keys:
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
                min_level=45,
                max_level=48,
                default_level=spec["default_level"],
                feature_type="blocked",
                movable=True,
                required=False,
                block_key="L",
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
        bind.execute(sa.text("DELETE FROM subscription_feature_blocks WHERE key = 'L'"))
    if _table_exists("conversation_chat_tags"):
        op.drop_table("conversation_chat_tags")
    if _table_exists("chat_tags"):
        op.drop_table("chat_tags")
    if "auto_translate" in _columns("conversation_members"):
        op.drop_column("conversation_members", "auto_translate")
