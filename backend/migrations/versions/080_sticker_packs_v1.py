"""sticker packs and installs

Revision ID: 080_sticker_packs_v1
Revises: 079_group_slow_mode_antiflood_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "080_sticker_packs_v1"
down_revision = "079_group_slow_mode_antiflood_v1"
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def upgrade() -> None:
    if not _table_exists("sticker_packs"):
        op.create_table(
            "sticker_packs",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("title", sa.String(length=120), nullable=False),
            sa.Column("slug", sa.String(length=140), nullable=False),
            sa.Column("owner_user_id", sa.Integer(), nullable=False),
            sa.Column("is_public", sa.Boolean(), nullable=False, server_default=sa.text("1")),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(), server_default=sa.func.now()),
            sa.ForeignKeyConstraint(["owner_user_id"], ["users.id"], ondelete="CASCADE"),
            sa.UniqueConstraint("slug", name="uq_sticker_packs_slug"),
        )
        op.create_index("ix_sticker_packs_slug", "sticker_packs", ["slug"], unique=False)
        op.create_index(
            "ix_sticker_packs_owner_user_id",
            "sticker_packs",
            ["owner_user_id"],
            unique=False,
        )
        op.create_index("ix_sticker_packs_is_public", "sticker_packs", ["is_public"], unique=False)

    if not _table_exists("stickers"):
        op.create_table(
            "stickers",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("pack_id", sa.Integer(), nullable=False),
            sa.Column("media_url", sa.String(length=512), nullable=False),
            sa.Column("emoji", sa.String(length=16), nullable=True),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
            sa.ForeignKeyConstraint(["pack_id"], ["sticker_packs.id"], ondelete="CASCADE"),
        )
        op.create_index("ix_stickers_pack_id", "stickers", ["pack_id"], unique=False)

    if not _table_exists("sticker_pack_installs"):
        op.create_table(
            "sticker_pack_installs",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), nullable=False),
            sa.Column("pack_id", sa.Integer(), nullable=False),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["pack_id"], ["sticker_packs.id"], ondelete="CASCADE"),
            sa.UniqueConstraint("user_id", "pack_id", name="uq_sticker_pack_install"),
        )
        op.create_index(
            "ix_sticker_pack_installs_user_id",
            "sticker_pack_installs",
            ["user_id"],
            unique=False,
        )
        op.create_index(
            "ix_sticker_pack_installs_pack_id",
            "sticker_pack_installs",
            ["pack_id"],
            unique=False,
        )


def downgrade() -> None:
    # Conservative downgrade to avoid destructive production rollback.
    pass
