"""bot miniapps platform v1

Revision ID: 062_bot_miniapps_platform_v1
Revises: 061_subscription_payment_id_unique_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "062_bot_miniapps_platform_v1"
down_revision = "061_subscription_payment_id_unique_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "bot_miniapps",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("bot_id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=64), nullable=False),
        sa.Column("short_name", sa.String(length=32), nullable=False),
        sa.Column("description", sa.String(length=512), nullable=True),
        sa.Column("url", sa.Text(), nullable=False),
        sa.Column("icon_url", sa.Text(), nullable=True),
        sa.Column("is_builtin", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("is_official", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=True),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.text("now()"), nullable=True),
        sa.ForeignKeyConstraint(["bot_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("bot_id", "short_name", name="uq_bot_miniapps_short_name"),
    )
    op.create_index("ix_bot_miniapps_id", "bot_miniapps", ["id"], unique=False)
    op.create_index("ix_bot_miniapps_bot_id", "bot_miniapps", ["bot_id"], unique=False)

    op.create_table(
        "miniapp_installs",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("miniapp_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("installed_at", sa.DateTime(), server_default=sa.text("now()"), nullable=True),
        sa.Column("last_launched_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["miniapp_id"], ["bot_miniapps.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("miniapp_id", "user_id", name="uq_miniapp_installs_user_app"),
    )
    op.create_index("ix_miniapp_installs_id", "miniapp_installs", ["id"], unique=False)
    op.create_index(
        "ix_miniapp_installs_miniapp_id", "miniapp_installs", ["miniapp_id"], unique=False
    )
    op.create_index("ix_miniapp_installs_user_id", "miniapp_installs", ["user_id"], unique=False)

    op.create_table(
        "miniapp_launches",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("miniapp_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=True),
        sa.Column("conversation_id", sa.Integer(), nullable=True),
        sa.Column("launched_at", sa.DateTime(), server_default=sa.text("now()"), nullable=True),
        sa.ForeignKeyConstraint(["miniapp_id"], ["bot_miniapps.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_miniapp_launches_id", "miniapp_launches", ["id"], unique=False)
    op.create_index("ix_miniapp_launches_miniapp_id", "miniapp_launches", ["miniapp_id"], unique=False)
    op.create_index("ix_miniapp_launches_user_id", "miniapp_launches", ["user_id"], unique=False)
    op.create_index(
        "ix_miniapp_launches_conversation_id", "miniapp_launches", ["conversation_id"], unique=False
    )
    op.create_index("ix_miniapp_launches_launched_at", "miniapp_launches", ["launched_at"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_miniapp_launches_launched_at", table_name="miniapp_launches")
    op.drop_index("ix_miniapp_launches_conversation_id", table_name="miniapp_launches")
    op.drop_index("ix_miniapp_launches_user_id", table_name="miniapp_launches")
    op.drop_index("ix_miniapp_launches_miniapp_id", table_name="miniapp_launches")
    op.drop_index("ix_miniapp_launches_id", table_name="miniapp_launches")
    op.drop_table("miniapp_launches")

    op.drop_index("ix_miniapp_installs_user_id", table_name="miniapp_installs")
    op.drop_index("ix_miniapp_installs_miniapp_id", table_name="miniapp_installs")
    op.drop_index("ix_miniapp_installs_id", table_name="miniapp_installs")
    op.drop_table("miniapp_installs")

    op.drop_index("ix_bot_miniapps_bot_id", table_name="bot_miniapps")
    op.drop_index("ix_bot_miniapps_id", table_name="bot_miniapps")
    op.drop_table("bot_miniapps")
