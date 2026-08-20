"""Append flex rungs 53–60 and premium tables/columns.

Revision ID: 141_flex_ladder_finish_v1
Revises: 140_flex_ladder_control_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "141_flex_ladder_finish_v1"
down_revision = "140_flex_ladder_control_v1"
branch_labels = None
depends_on = None

_BLOCKS = (
    {
        "key": "N",
        "title": "Premium+",
        "min_level": 53,
        "max_level": 56,
        "sort_order": 14,
    },
    {
        "key": "O",
        "title": "Ещё Premium",
        "min_level": 57,
        "max_level": 60,
        "sort_order": 15,
    },
)

_FEATURES = (
    {
        "slug": "gif_favorites",
        "title": "Избранные GIF",
        "description": "Сохранять GIF в облако и вставлять их с любого устройства.",
        "icon": "favorite",
        "default_level": 53,
        "block_key": "N",
        "min_level": 53,
        "max_level": 56,
    },
    {
        "slug": "story_archive",
        "title": "Архив сторис",
        "description": "Свои истёкшие сторис остаются в архиве, а не исчезают.",
        "icon": "inventory_2",
        "default_level": 54,
        "block_key": "N",
        "min_level": 53,
        "max_level": 56,
    },
    {
        "slug": "story_tray_priority",
        "title": "Приоритет сторис",
        "description": "Ваши сторис показываются выше в ленте у других.",
        "icon": "trending_up",
        "default_level": 55,
        "block_key": "N",
        "min_level": 53,
        "max_level": 56,
    },
    {
        "slug": "group_add_privacy",
        "title": "Кто добавляет в группы",
        "description": "Ограничить, кто может добавлять вас в группы: все, контакты или никто.",
        "icon": "group_off",
        "default_level": 56,
        "block_key": "N",
        "min_level": 53,
        "max_level": 56,
    },
    {
        "slug": "folder_share",
        "title": "Поделиться папкой",
        "description": "Отправить ссылку на папку чатов — получатель импортирует её себе.",
        "icon": "share",
        "default_level": 57,
        "block_key": "O",
        "min_level": 57,
        "max_level": 60,
    },
    {
        "slug": "story_caption_plus",
        "title": "Длинные подписи сторис",
        "description": "Подпись к сторис до 1000 символов вместо 500.",
        "icon": "notes",
        "default_level": 58,
        "block_key": "O",
        "min_level": 57,
        "max_level": 60,
    },
    {
        "slug": "animated_avatar",
        "title": "Анимированный аватар",
        "description": "Поставить GIF как фото профиля — оно будет двигаться.",
        "icon": "gif",
        "default_level": 59,
        "block_key": "O",
        "min_level": 57,
        "max_level": 60,
    },
    {
        "slug": "quick_replies",
        "title": "Быстрые ответы",
        "description": "Заготовки текста над полем ввода — вставить одним нажатием.",
        "icon": "quickreply",
        "default_level": 60,
        "block_key": "O",
        "min_level": 57,
        "max_level": 60,
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
    if "keep_in_archive" not in _columns("stories") and _table_exists("stories"):
        op.add_column(
            "stories",
            sa.Column(
                "keep_in_archive",
                sa.Boolean(),
                nullable=False,
                server_default=sa.false(),
            ),
        )
    if "group_add_privacy" not in _columns("users") and _table_exists("users"):
        op.add_column(
            "users",
            sa.Column(
                "group_add_privacy",
                sa.String(20),
                nullable=False,
                server_default="everybody",
            ),
        )
    if not _table_exists("gif_favorites"):
        op.create_table(
            "gif_favorites",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("media_url", sa.String(1024), nullable=False),
            sa.Column("preview_url", sa.String(1024), nullable=True),
            sa.Column("title", sa.String(80), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=True),
            sa.UniqueConstraint("user_id", "media_url", name="uq_gif_favorite_user_url"),
        )
        op.create_index("ix_gif_favorites_user_id", "gif_favorites", ["user_id"])
    if not _table_exists("chat_folder_shares"):
        op.create_table(
            "chat_folder_shares",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("token", sa.String(64), nullable=False),
            sa.Column(
                "folder_id",
                sa.Integer(),
                sa.ForeignKey("chat_folders.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "owner_user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("created_at", sa.DateTime(), nullable=True),
            sa.Column("revoked_at", sa.DateTime(), nullable=True),
            sa.UniqueConstraint("token", name="uq_chat_folder_share_token"),
        )
        op.create_index("ix_chat_folder_shares_token", "chat_folder_shares", ["token"])
    if not _table_exists("quick_replies"):
        op.create_table(
            "quick_replies",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("title", sa.String(40), nullable=False),
            sa.Column("text", sa.String(400), nullable=False),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        )
        op.create_index("ix_quick_replies_user_id", "quick_replies", ["user_id"])

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
    for spec in _BLOCKS:
        if spec["key"] not in existing_keys:
            bind.execute(blocks.insert().values(**spec))

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
                min_level=spec["min_level"],
                max_level=spec["max_level"],
                default_level=spec["default_level"],
                feature_type="blocked",
                movable=True,
                required=False,
                block_key=spec["block_key"],
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
        bind.execute(sa.text("DELETE FROM subscription_feature_blocks WHERE key IN ('N', 'O')"))
    if _table_exists("quick_replies"):
        op.drop_table("quick_replies")
    if _table_exists("chat_folder_shares"):
        op.drop_table("chat_folder_shares")
    if _table_exists("gif_favorites"):
        op.drop_table("gif_favorites")
    if "group_add_privacy" in _columns("users"):
        op.drop_column("users", "group_add_privacy")
    if "keep_in_archive" in _columns("stories"):
        op.drop_column("stories", "keep_in_archive")
