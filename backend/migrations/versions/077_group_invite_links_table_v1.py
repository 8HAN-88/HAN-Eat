"""group invite links table

Revision ID: 077_group_invite_links_table_v1
Revises: 076_group_join_requests_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "077_group_invite_links_table_v1"
down_revision = "076_group_join_requests_v1"
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def _index_exists(table_name: str, index_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if table_name not in inspector.get_table_names():
        return False
    return any(idx.get("name") == index_name for idx in inspector.get_indexes(table_name))


def upgrade() -> None:
    if not _table_exists("group_invite_links"):
        op.create_table(
            "group_invite_links",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("conversation_id", sa.Integer(), nullable=False),
            sa.Column("token", sa.String(length=96), nullable=False),
            sa.Column("created_by_user_id", sa.Integer(), nullable=True),
            sa.Column("expires_at", sa.DateTime(), nullable=True),
            sa.Column("max_uses", sa.Integer(), nullable=True),
            sa.Column("uses_count", sa.Integer(), nullable=False, server_default=sa.text("0")),
            sa.Column("revoked_at", sa.DateTime(), nullable=True),
            sa.Column(
                "created_at",
                sa.DateTime(),
                nullable=True,
                server_default=sa.text("CURRENT_TIMESTAMP"),
            ),
            sa.ForeignKeyConstraint(["conversation_id"], ["conversations.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
            sa.PrimaryKeyConstraint("id"),
            sa.CheckConstraint(
                "max_uses IS NULL OR max_uses > 0",
                name="check_group_invite_links_max_uses",
            ),
            sa.UniqueConstraint("token"),
        )
    if not _index_exists("group_invite_links", "ix_group_invite_links_conversation_id"):
        op.create_index(
            "ix_group_invite_links_conversation_id",
            "group_invite_links",
            ["conversation_id"],
            unique=False,
        )
    if not _index_exists("group_invite_links", "ix_group_invite_links_token"):
        op.create_index(
            "ix_group_invite_links_token",
            "group_invite_links",
            ["token"],
            unique=True,
        )
    if not _index_exists("group_invite_links", "ix_group_invite_links_expires_at"):
        op.create_index(
            "ix_group_invite_links_expires_at",
            "group_invite_links",
            ["expires_at"],
            unique=False,
        )
    if not _index_exists("group_invite_links", "ix_group_invite_links_revoked_at"):
        op.create_index(
            "ix_group_invite_links_revoked_at",
            "group_invite_links",
            ["revoked_at"],
            unique=False,
        )

    # Backfill existing single invite token into links table.
    bind = op.get_bind()
    if _table_exists("conversations"):
        rows = bind.execute(
            sa.text(
                """
                SELECT id, invite_token, created_by_user_id, invite_token_updated_at, created_at
                FROM conversations
                WHERE type = 'group' AND invite_token IS NOT NULL
                """
            )
        ).fetchall()
        for row in rows:
            bind.execute(
                sa.text(
                    """
                    INSERT INTO group_invite_links
                        (conversation_id, token, created_by_user_id, created_at, uses_count)
                    VALUES
                        (:conversation_id, :token, :created_by_user_id, :created_at, 0)
                    ON CONFLICT (token) DO NOTHING
                    """
                ),
                {
                    "conversation_id": row.id,
                    "token": row.invite_token,
                    "created_by_user_id": row.created_by_user_id,
                    "created_at": row.invite_token_updated_at or row.created_at,
                },
            )


def downgrade() -> None:
    # Keep downgrade conservative to avoid destructive rollback on production data.
    pass
