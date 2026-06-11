"""Backfill channel_id on posts published to channels

Revision ID: 044_backfill_channel_post_ids
Revises: 043_remove_exclusive_pro_v1
"""
from alembic import op

revision = "044_backfill_channel_post_ids"
down_revision = "043_remove_exclusive_pro_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        UPDATE posts AS p
        SET channel_id = matched.cid
        FROM (
            SELECT p2.id AS post_id,
                   CAST(regexp_replace(elem, '^channel:', '') AS INTEGER) AS cid
            FROM posts AS p2,
                 unnest(p2.publish_to) AS elem
            WHERE p2.channel_id IS NULL
              AND p2.publish_to IS NOT NULL
              AND elem LIKE 'channel:%'
        ) AS matched
        WHERE p.id = matched.post_id
          AND p.channel_id IS NULL
        """
    )


def downgrade() -> None:
    pass
