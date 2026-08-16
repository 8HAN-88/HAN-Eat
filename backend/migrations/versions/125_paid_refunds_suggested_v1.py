"""Stars refunds, Premium giveaways, suggested channel posts.

Revision ID: 125_paid_refunds_suggested_v1
Revises: 123_anonymous_star_gifts_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "125_paid_refunds_suggested_v1"
down_revision = "123_anonymous_star_gifts_v1"
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def _column_exists(table_name: str, column_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if table_name not in inspector.get_table_names():
        return False
    return any(c["name"] == column_name for c in inspector.get_columns(table_name))


def upgrade() -> None:
    if _table_exists("star_giveaways"):
        if not _column_exists("star_giveaways", "prize_type"):
            op.add_column(
                "star_giveaways",
                sa.Column(
                    "prize_type",
                    sa.String(length=16),
                    nullable=False,
                    server_default="stars",
                ),
            )
        if not _column_exists("star_giveaways", "premium_months"):
            op.add_column(
                "star_giveaways",
                sa.Column(
                    "premium_months",
                    sa.Integer(),
                    nullable=False,
                    server_default="0",
                ),
            )

    if not _table_exists("channel_suggested_posts"):
        op.create_table(
            "channel_suggested_posts",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "channel_id",
                sa.Integer(),
                sa.ForeignKey("channels.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "author_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("text", sa.String(length=2000), nullable=False),
            sa.Column("media_url", sa.String(length=1024), nullable=True),
            sa.Column("amount_stars", sa.Integer(), nullable=False),
            sa.Column(
                "status",
                sa.String(length=24),
                nullable=False,
                server_default="pending",
            ),
            sa.Column(
                "post_id",
                sa.Integer(),
                sa.ForeignKey("posts.id", ondelete="SET NULL"),
                nullable=True,
            ),
            sa.Column(
                "created_at",
                sa.DateTime(),
                server_default=sa.func.now(),
                nullable=False,
            ),
        )
        op.create_index(
            "ix_channel_suggested_posts_channel_id",
            "channel_suggested_posts",
            ["channel_id"],
        )
        op.create_index(
            "ix_channel_suggested_posts_status",
            "channel_suggested_posts",
            ["status"],
        )


def downgrade() -> None:
    if _table_exists("channel_suggested_posts"):
        op.drop_index(
            "ix_channel_suggested_posts_status",
            table_name="channel_suggested_posts",
        )
        op.drop_index(
            "ix_channel_suggested_posts_channel_id",
            table_name="channel_suggested_posts",
        )
        op.drop_table("channel_suggested_posts")
    if _table_exists("star_giveaways"):
        if _column_exists("star_giveaways", "premium_months"):
            op.drop_column("star_giveaways", "premium_months")
        if _column_exists("star_giveaways", "prize_type"):
            op.drop_column("star_giveaways", "prize_type")
