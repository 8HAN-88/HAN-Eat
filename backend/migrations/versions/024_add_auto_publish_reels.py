"""Add auto_publish_reels flag to channels

Revision ID: 024_auto_publish_reels
Revises: 023_base_recipes
Create Date: 2026-02-03
"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '024_auto_publish_reels'
down_revision = '023_base_recipes'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'channels',
        sa.Column(
            'auto_publish_reels',
            sa.Boolean(),
            server_default=sa.true(),
            nullable=False,
        ),
    )
    # Ensure existing channels default to True
    op.execute("UPDATE channels SET auto_publish_reels = TRUE")
    op.alter_column('channels', 'auto_publish_reels', server_default=None)


def downgrade() -> None:
    op.drop_column('channels', 'auto_publish_reels')
