"""Append flex rungs 61–68 and Telegram Business tables.

Revision ID: 142_flex_ladder_business_v1
Revises: 141_flex_ladder_finish_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "142_flex_ladder_business_v1"
down_revision = "141_flex_ladder_finish_v1"
branch_labels = None
depends_on = None

_BLOCKS = (
    {
        "key": "P",
        "title": "Бизнес",
        "min_level": 61,
        "max_level": 64,
        "sort_order": 16,
    },
    {
        "key": "Q",
        "title": "Ещё бизнес",
        "min_level": 65,
        "max_level": 68,
        "sort_order": 17,
    },
)

_FEATURES = (
    {
        "slug": "business_greeting",
        "title": "Приветствие",
        "description": "Автоответ тем, кто пишет вам впервые или после паузы.",
        "icon": "waving_hand",
        "default_level": 61,
        "block_key": "P",
        "min_level": 61,
        "max_level": 64,
    },
    {
        "slug": "business_away",
        "title": "Меня нет",
        "description": "Автоответ, пока выключили приём или вне часов работы.",
        "icon": "beach_access",
        "default_level": 62,
        "block_key": "P",
        "min_level": 61,
        "max_level": 64,
    },
    {
        "slug": "business_hours",
        "title": "Часы работы",
        "description": "Расписание на профиле: открыто или закрыто прямо сейчас.",
        "icon": "schedule",
        "default_level": 63,
        "block_key": "P",
        "min_level": 61,
        "max_level": 64,
    },
    {
        "slug": "business_location",
        "title": "Адрес на карте",
        "description": "Точка и адрес в профиле — открывается в картах.",
        "icon": "place",
        "default_level": 64,
        "block_key": "P",
        "min_level": 61,
        "max_level": 64,
    },
    {
        "slug": "business_intro",
        "title": "Стартовая страница",
        "description": "Заголовок и текст интро в профиле, как у Telegram Business.",
        "icon": "web_stories",
        "default_level": 65,
        "block_key": "Q",
        "min_level": 65,
        "max_level": 68,
    },
    {
        "slug": "business_bot",
        "title": "Бот поддержки",
        "description": "Привязать своего бота к профилю — клиент пишет ему в один тап.",
        "icon": "smart_toy",
        "default_level": 66,
        "block_key": "Q",
        "min_level": 65,
        "max_level": 68,
    },
    {
        "slug": "dm_privacy",
        "title": "Кто пишет первым",
        "description": "Кто может начать с вами новый личный чат: все, контакты или никто.",
        "icon": "mail_lock",
        "default_level": 67,
        "block_key": "Q",
        "min_level": 65,
        "max_level": 68,
    },
    {
        "slug": "profile_website",
        "title": "Сайт в профиле",
        "description": "Ссылка на сайт или соцсеть под описанием профиля.",
        "icon": "link",
        "default_level": 68,
        "block_key": "Q",
        "min_level": 65,
        "max_level": 68,
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
    if "dm_privacy" not in _columns("users") and _table_exists("users"):
        op.add_column(
            "users",
            sa.Column(
                "dm_privacy",
                sa.String(20),
                nullable=False,
                server_default="everybody",
            ),
        )
    if not _table_exists("user_business_settings"):
        op.create_table(
            "user_business_settings",
            sa.Column(
                "user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                primary_key=True,
            ),
            sa.Column("greeting_enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
            sa.Column("greeting_text", sa.String(400), nullable=True),
            sa.Column(
                "greeting_inactivity_days",
                sa.Integer(),
                nullable=False,
                server_default="7",
            ),
            sa.Column("away_enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
            sa.Column("away_text", sa.String(400), nullable=True),
            sa.Column("away_mode", sa.String(20), nullable=False, server_default="manual"),
            sa.Column("hours_json", sa.Text(), nullable=True),
            sa.Column("location_lat", sa.Float(), nullable=True),
            sa.Column("location_lng", sa.Float(), nullable=True),
            sa.Column("location_address", sa.String(120), nullable=True),
            sa.Column("intro_title", sa.String(40), nullable=True),
            sa.Column("intro_text", sa.String(200), nullable=True),
            sa.Column("intro_sticker_url", sa.String(1024), nullable=True),
            sa.Column(
                "support_bot_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="SET NULL"),
                nullable=True,
            ),
            sa.Column("website_url", sa.String(200), nullable=True),
            sa.Column("updated_at", sa.DateTime(), nullable=True),
        )
    if not _table_exists("business_auto_replies"):
        op.create_table(
            "business_auto_replies",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "owner_user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "peer_user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("kind", sa.String(16), nullable=False),
            sa.Column("sent_at", sa.DateTime(), nullable=False),
            sa.UniqueConstraint(
                "owner_user_id",
                "peer_user_id",
                "kind",
                name="uq_business_auto_reply",
            ),
        )
        op.create_index(
            "ix_business_auto_replies_owner_user_id",
            "business_auto_replies",
            ["owner_user_id"],
        )
        op.create_index(
            "ix_business_auto_replies_peer_user_id",
            "business_auto_replies",
            ["peer_user_id"],
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
        bind.execute(sa.text("DELETE FROM subscription_feature_blocks WHERE key IN ('P', 'Q')"))
    if _table_exists("business_auto_replies"):
        op.drop_table("business_auto_replies")
    if _table_exists("user_business_settings"):
        op.drop_table("user_business_settings")
    if "dm_privacy" in _columns("users"):
        op.drop_column("users", "dm_privacy")
