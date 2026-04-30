"""Add reposts table

Revision ID: 004_reposts
Revises: 003_channels
Create Date: 2025-01-XX

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '004_reposts'
down_revision = '003_channels'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Reposts table
    op.create_table(
        'reposts',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('post_id', sa.Integer(), nullable=False),
        sa.Column('comment', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()'), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['post_id'], ['posts.id'], ondelete='CASCADE'),
        sa.UniqueConstraint('user_id', 'post_id', name='uq_repost_user_post'),
    )
    op.create_index(op.f('ix_reposts_id'), 'reposts', ['id'], unique=False)
    op.create_index(op.f('ix_reposts_user_id'), 'reposts', ['user_id'], unique=False)
    op.create_index(op.f('ix_reposts_post_id'), 'reposts', ['post_id'], unique=False)
    op.create_index(op.f('ix_reposts_created_at'), 'reposts', ['created_at'], unique=False)
    
    # Добавляем поле reposts_count в posts (опционально, можно считать через JOIN)
    # Пока не добавляем, будем считать через COUNT


def downgrade() -> None:
    op.drop_index(op.f('ix_reposts_created_at'), table_name='reposts')
    op.drop_index(op.f('ix_reposts_post_id'), table_name='reposts')
    op.drop_index(op.f('ix_reposts_user_id'), table_name='reposts')
    op.drop_index(op.f('ix_reposts_id'), table_name='reposts')
    op.drop_table('reposts')

