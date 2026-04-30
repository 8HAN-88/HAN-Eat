"""Add fcm_token to users

Revision ID: 011_add_fcm_token
Revises: 010_add_is_admin_is_moderator
Create Date: 2025-01-XX

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '011_add_fcm_token'
down_revision = '010_add_is_admin_is_moderator'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add fcm_token column to users table
    op.add_column('users', sa.Column('fcm_token', sa.String(length=500), nullable=True))
    op.create_index(op.f('ix_users_fcm_token'), 'users', ['fcm_token'], unique=False)


def downgrade() -> None:
    # Remove fcm_token column from users table
    op.drop_index(op.f('ix_users_fcm_token'), table_name='users')
    op.drop_column('users', 'fcm_token')

