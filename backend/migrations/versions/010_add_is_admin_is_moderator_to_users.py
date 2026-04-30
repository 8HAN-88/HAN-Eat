"""Add is_admin and is_moderator to users

Revision ID: 010_add_is_admin_is_moderator
Revises: 009_support
Create Date: 2025-01-XX

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '010_add_is_admin_is_moderator'
down_revision = '009_support'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add is_admin and is_moderator columns to users table
    op.add_column('users', sa.Column('is_admin', sa.Boolean(), nullable=False, server_default='false'))
    op.add_column('users', sa.Column('is_moderator', sa.Boolean(), nullable=False, server_default='false'))


def downgrade() -> None:
    # Remove is_admin and is_moderator columns from users table
    op.drop_column('users', 'is_moderator')
    op.drop_column('users', 'is_admin')

