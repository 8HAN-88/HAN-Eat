"""Rename analytics_events.metadata to event_metadata

Revision ID: 020_analytics_metadata
Revises: 019_extend_channels_for_full_tz
Create Date: 2025-12-12

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '020_analytics_metadata'
down_revision = '019_extend_channels'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Переименовываем колонку metadata в event_metadata
    op.alter_column('analytics_events', 'metadata', new_column_name='event_metadata')


def downgrade() -> None:
    # Возвращаем обратно
    op.alter_column('analytics_events', 'event_metadata', new_column_name='metadata')

