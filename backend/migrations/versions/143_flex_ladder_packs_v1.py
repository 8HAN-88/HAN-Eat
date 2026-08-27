"""Append flex rungs 69–72 and pack marketplace tables.

Revision ID: 143_flex_ladder_packs_v1
Revises: 142_flex_ladder_business_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "143_flex_ladder_packs_v1"
down_revision = "142_flex_ladder_business_v1"
branch_labels = None
depends_on = None

_BLOCKS = (
    {
        "key": "R",
        "title": "Магазин",
        "min_level": 69,
        "max_level": 72,
        "sort_order": 18,
    },
)

_FEATURES = (
    {
        "slug": "custom_emoji",
        "title": "Свои эмодзи",
        "description": "Вставлять купленные кастомные эмодзи прямо в текст сообщений.",
        "icon": "emoji_emotions",
        "default_level": 69,
        "block_key": "R",
        "min_level": 69,
        "max_level": 72,
    },
    {
        "slug": "emoji_pack_publish",
        "title": "Продажа эмодзи",
        "description": "Выложить свой пак кастомных эмодзи в магазин и получать Stars за покупки.",
        "icon": "storefront",
        "default_level": 70,
        "block_key": "R",
        "min_level": 69,
        "max_level": 72,
    },
    {
        "slug": "sticker_pack_sell",
        "title": "Продажа стикеров",
        "description": "Выставить стикерпак на витрину за Stars — площадка берёт комиссию 5%.",
        "icon": "sell",
        "default_level": 71,
        "block_key": "R",
        "min_level": 69,
        "max_level": 72,
    },
    {
        "slug": "custom_emoji_reactions",
        "title": "Реакции своими эмодзи",
        "description": "Ставить реакции кастомными эмодзи из купленных паков.",
        "icon": "add_reaction",
        "default_level": 72,
        "block_key": "R",
        "min_level": 69,
        "max_level": 72,
    },
)


def _table_exists(table_name: str) -> bool:
    inspector = sa.inspect(op.get_bind())
    return table_name in inspector.get_table_names()


def _columns(table_name: str) -> set[str]:
    inspector = sa.inspect(op.get_bind())
    if table_name not in inspector.get_table_names():
        return set()
    return {col["name"] for col in inspector.get_columns(table_name)}


def upgrade() -> None:
    bind = op.get_bind()
    if _table_exists("users") and "emoji_status" in _columns("users"):
        op.alter_column(
            "users",
            "emoji_status",
            existing_type=sa.String(length=16),
            type_=sa.String(length=32),
            existing_nullable=True,
        )
    if _table_exists("message_reactions"):
        op.alter_column(
            "message_reactions",
            "emoji",
            existing_type=sa.String(length=16),
            type_=sa.String(length=32),
            existing_nullable=False,
        )
    if _table_exists("sticker_packs"):
        cols = _columns("sticker_packs")
        if "price_stars" not in cols:
            op.add_column(
                "sticker_packs",
                sa.Column("price_stars", sa.Integer(), nullable=False, server_default="0"),
            )
        if "listed_at" not in cols:
            op.add_column("sticker_packs", sa.Column("listed_at", sa.DateTime(), nullable=True))
    if not _table_exists("sticker_pack_purchases"):
        op.create_table(
            "sticker_pack_purchases",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column(
                "pack_id",
                sa.Integer(),
                sa.ForeignKey("sticker_packs.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("seller_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
            sa.Column("amount_stars", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("fee_stars", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(), nullable=True),
            sa.UniqueConstraint("user_id", "pack_id", name="uq_sticker_pack_purchase"),
        )
        op.create_index("ix_sticker_pack_purchases_user_id", "sticker_pack_purchases", ["user_id"])
        op.create_index("ix_sticker_pack_purchases_pack_id", "sticker_pack_purchases", ["pack_id"])
    if not _table_exists("emoji_packs"):
        op.create_table(
            "emoji_packs",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("title", sa.String(120), nullable=False),
            sa.Column("slug", sa.String(140), nullable=False),
            sa.Column("owner_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("is_public", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("price_stars", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("listed_at", sa.DateTime(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=True),
            sa.Column("updated_at", sa.DateTime(), nullable=True),
            sa.UniqueConstraint("slug", name="uq_emoji_packs_slug"),
        )
        op.create_index("ix_emoji_packs_slug", "emoji_packs", ["slug"], unique=True)
        op.create_index("ix_emoji_packs_owner_user_id", "emoji_packs", ["owner_user_id"])
    if not _table_exists("custom_emojis"):
        op.create_table(
            "custom_emojis",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("pack_id", sa.Integer(), sa.ForeignKey("emoji_packs.id", ondelete="CASCADE"), nullable=False),
            sa.Column("media_url", sa.String(512), nullable=False),
            sa.Column("shortcode", sa.String(32), nullable=True),
            sa.Column("order_index", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(), nullable=True),
        )
        op.create_index("ix_custom_emojis_pack_id", "custom_emojis", ["pack_id"])
    if not _table_exists("emoji_pack_installs"):
        op.create_table(
            "emoji_pack_installs",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("pack_id", sa.Integer(), sa.ForeignKey("emoji_packs.id", ondelete="CASCADE"), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=True),
            sa.UniqueConstraint("user_id", "pack_id", name="uq_emoji_pack_install"),
        )
    if not _table_exists("emoji_pack_purchases"):
        op.create_table(
            "emoji_pack_purchases",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("pack_id", sa.Integer(), sa.ForeignKey("emoji_packs.id", ondelete="CASCADE"), nullable=False),
            sa.Column("seller_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
            sa.Column("amount_stars", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("fee_stars", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(), nullable=True),
            sa.UniqueConstraint("user_id", "pack_id", name="uq_emoji_pack_purchase"),
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
        bind.execute(sa.text("DELETE FROM subscription_feature_blocks WHERE key = 'R'"))
    if _table_exists("emoji_pack_purchases"):
        op.drop_table("emoji_pack_purchases")
    if _table_exists("emoji_pack_installs"):
        op.drop_table("emoji_pack_installs")
    if _table_exists("custom_emojis"):
        op.drop_table("custom_emojis")
    if _table_exists("emoji_packs"):
        op.drop_table("emoji_packs")
    if _table_exists("sticker_pack_purchases"):
        op.drop_table("sticker_pack_purchases")
    if "listed_at" in _columns("sticker_packs"):
        op.drop_column("sticker_packs", "listed_at")
    if "price_stars" in _columns("sticker_packs"):
        op.drop_column("sticker_packs", "price_stars")
