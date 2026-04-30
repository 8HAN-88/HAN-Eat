"""Add analytics events table

Revision ID: 006_analytics
Revises: 005_moderation
Create Date: 2025-01-XX

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '006_analytics'
down_revision = '005_moderation'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Analytics Events table
    op.create_table(
        'analytics_events',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('event_type', sa.String(length=50), nullable=False),
        sa.Column('entity_type', sa.String(length=20), nullable=False),
        sa.Column('entity_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=True),
        sa.Column('author_id', sa.Integer(), nullable=True),
        sa.Column('metadata', postgresql.JSON(astext_type=sa.Text()), nullable=True),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()'), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['author_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_analytics_events_id'), 'analytics_events', ['id'], unique=False)
    op.create_index(op.f('ix_analytics_events_event_type'), 'analytics_events', ['event_type'], unique=False)
    op.create_index(op.f('ix_analytics_events_entity_type'), 'analytics_events', ['entity_type'], unique=False)
    op.create_index(op.f('ix_analytics_events_entity_id'), 'analytics_events', ['entity_id'], unique=False)
    op.create_index(op.f('ix_analytics_events_user_id'), 'analytics_events', ['user_id'], unique=False)
    op.create_index(op.f('ix_analytics_events_author_id'), 'analytics_events', ['author_id'], unique=False)
    op.create_index(op.f('ix_analytics_events_created_at'), 'analytics_events', ['created_at'], unique=False)
    
    # Составные индексы для быстрых запросов
    op.create_index(
        'ix_analytics_author_event',
        'analytics_events',
        ['author_id', 'event_type', 'created_at'],
        unique=False
    )
    op.create_index(
        'ix_analytics_entity',
        'analytics_events',
        ['entity_type', 'entity_id', 'event_type'],
        unique=False
    )


def downgrade() -> None:
    op.drop_index('ix_analytics_entity', table_name='analytics_events')
    op.drop_index('ix_analytics_author_event', table_name='analytics_events')
    op.drop_index(op.f('ix_analytics_events_created_at'), table_name='analytics_events')
    op.drop_index(op.f('ix_analytics_events_author_id'), table_name='analytics_events')
    op.drop_index(op.f('ix_analytics_events_user_id'), table_name='analytics_events')
    op.drop_index(op.f('ix_analytics_events_entity_id'), table_name='analytics_events')
    op.drop_index(op.f('ix_analytics_events_entity_type'), table_name='analytics_events')
    op.drop_index(op.f('ix_analytics_events_event_type'), table_name='analytics_events')
    op.drop_index(op.f('ix_analytics_events_id'), table_name='analytics_events')
    op.drop_table('analytics_events')

