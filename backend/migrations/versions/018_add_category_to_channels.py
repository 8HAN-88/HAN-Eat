"""add category to channels

Revision ID: 018_add_category_to_channels
Revises: 017_add_country_code
Create Date: 2025-12-10 17:30:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '018_add_category_to_channels'
down_revision = '017_add_country_code'
branch_labels = None
depends_on = None


def upgrade():
    # Добавляем поле category в таблицу channels
    op.add_column('channels', sa.Column('category', sa.String(length=50), nullable=True))
    op.create_index('ix_channels_category', 'channels', ['category'])


def downgrade():
    op.drop_index('ix_channels_category', table_name='channels')
    op.drop_column('channels', 'category')

