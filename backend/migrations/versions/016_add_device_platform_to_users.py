"""add device_platform to users

Revision ID: 016_add_device_platform_to_users
Revises: 015_add_fulltext_search_indexes
Create Date: 2025-01-XX

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '016_add_device_platform_to_users'
down_revision = '015_add_fulltext_search_indexes'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Добавляем поле device_platform для определения платформы устройства
    op.add_column('users', sa.Column('device_platform', sa.String(length=20), nullable=True))
    # Создаем индекс для быстрого поиска по платформе
    op.create_index('ix_users_device_platform', 'users', ['device_platform'])


def downgrade() -> None:
    op.drop_index('ix_users_device_platform', table_name='users')
    op.drop_column('users', 'device_platform')

