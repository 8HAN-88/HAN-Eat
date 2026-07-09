"""group invite links backfill

Revision ID: 078_group_invite_links_backfill_v1
Revises: 077_group_invite_links_table_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "078_group_invite_links_backfill_v1"
down_revision = "077_group_invite_links_table_v1"
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def upgrade() -> None:
    bind = op.get_bind()
    if not (_table_exists("conversations") and _table_exists("group_invite_links")):
        return

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
