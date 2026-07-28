"""sticker favorites + pinned packs

Revision ID: 098_sticker_favorites_pins_v1
Revises: 097_media_group_id_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "098_sticker_favorites_pins_v1"
down_revision = "097_media_group_id_v1"
branch_labels = None
depends_on = None


def _tables() -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return set(inspector.get_table_names())


def upgrade() -> None:
    tables = _tables()
    if "sticker_favorites" not in tables:
        op.create_table(
            "sticker_favorites",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "sticker_id",
                sa.Integer(),
                sa.ForeignKey("stickers.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "created_at",
                sa.DateTime(),
                server_default=sa.text("now()"),
                nullable=False,
            ),
            sa.UniqueConstraint(
                "user_id", "sticker_id", name="uq_sticker_favorite_user_sticker"
            ),
        )
        op.create_index(
            "ix_sticker_favorites_user_id", "sticker_favorites", ["user_id"]
        )
        op.create_index(
            "ix_sticker_favorites_sticker_id",
            "sticker_favorites",
            ["sticker_id"],
        )
        op.create_index(
            "ix_sticker_favorites_user_created",
            "sticker_favorites",
            ["user_id", "created_at"],
        )

    tables = _tables()
    if "sticker_pack_pins" not in tables:
        op.create_table(
            "sticker_pack_pins",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "pack_id",
                sa.Integer(),
                sa.ForeignKey("sticker_packs.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("pin_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column(
                "created_at",
                sa.DateTime(),
                server_default=sa.text("now()"),
                nullable=False,
            ),
            sa.UniqueConstraint(
                "user_id", "pack_id", name="uq_sticker_pack_pin_user_pack"
            ),
        )
        op.create_index(
            "ix_sticker_pack_pins_user_id", "sticker_pack_pins", ["user_id"]
        )
        op.create_index(
            "ix_sticker_pack_pins_pack_id", "sticker_pack_pins", ["pack_id"]
        )
        op.create_index(
            "ix_sticker_pack_pins_user_order",
            "sticker_pack_pins",
            ["user_id", "pin_order"],
        )


def downgrade() -> None:
    tables = _tables()
    if "sticker_pack_pins" in tables:
        op.drop_table("sticker_pack_pins")
    tables = _tables()
    if "sticker_favorites" in tables:
        op.drop_table("sticker_favorites")
