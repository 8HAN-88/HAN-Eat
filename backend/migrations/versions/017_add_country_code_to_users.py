"""Add country_code to users

Revision ID: 017_add_country_code
Revises: 016_add_device_platform_to_users
Create Date: 2025-01-XX

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '017_add_country_code'
down_revision = '016_add_device_platform_to_users'
branch_labels = None
depends_on = None


def upgrade():
    # Add country_code column to users table
    op.add_column('users', sa.Column('country_code', sa.String(length=2), nullable=True))
    op.create_index(op.f('ix_users_country_code'), 'users', ['country_code'], unique=False)


def downgrade():
    # Remove country_code column from users table
    op.drop_index(op.f('ix_users_country_code'), table_name='users')
    op.drop_column('users', 'country_code')

