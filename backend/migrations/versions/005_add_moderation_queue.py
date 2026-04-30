"""Add moderation queue table

Revision ID: 005_moderation
Revises: 004_reposts
Create Date: 2025-01-XX

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '005_moderation'
down_revision = '004_reposts'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Moderation Queue table
    op.create_table(
        'moderation_queue',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('content_type', sa.String(length=20), nullable=False),
        sa.Column('content_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=True),
        sa.Column('status', sa.String(length=20), nullable=True),
        sa.Column('reason', sa.String(length=20), nullable=True),
        sa.Column('flagged_by_user_id', sa.Integer(), nullable=True),
        sa.Column('moderation_comment', sa.Text(), nullable=True),
        sa.Column('rejection_reason', sa.String(length=50), nullable=True),
        sa.Column('moderated_by_user_id', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()'), nullable=True),
        sa.Column('moderated_at', sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['flagged_by_user_id'], ['users.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['moderated_by_user_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_moderation_queue_id'), 'moderation_queue', ['id'], unique=False)
    op.create_index(op.f('ix_moderation_queue_content_type'), 'moderation_queue', ['content_type'], unique=False)
    op.create_index(op.f('ix_moderation_queue_content_id'), 'moderation_queue', ['id'], unique=False)
    op.create_index(op.f('ix_moderation_queue_user_id'), 'moderation_queue', ['user_id'], unique=False)
    op.create_index(op.f('ix_moderation_queue_status'), 'moderation_queue', ['status'], unique=False)
    op.create_index(op.f('ix_moderation_queue_created_at'), 'moderation_queue', ['created_at'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_moderation_queue_created_at'), table_name='moderation_queue')
    op.drop_index(op.f('ix_moderation_queue_status'), table_name='moderation_queue')
    op.drop_index(op.f('ix_moderation_queue_user_id'), table_name='moderation_queue')
    op.drop_index(op.f('ix_moderation_queue_content_id'), table_name='moderation_queue')
    op.drop_index(op.f('ix_moderation_queue_content_type'), table_name='moderation_queue')
    op.drop_index(op.f('ix_moderation_queue_id'), table_name='moderation_queue')
    op.drop_table('moderation_queue')

