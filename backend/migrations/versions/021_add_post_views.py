"""Add post views tracking

Revision ID: 021_post_views
Revises: 020_analytics_metadata
Create Date: 2025-12-22

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '021_post_views'
down_revision = '020_analytics_metadata'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Добавляем счетчик просмотров в posts
    op.add_column('posts', sa.Column('views_count', sa.Integer(), nullable=True, server_default='0'))
    
    # Создаем таблицу для отслеживания просмотров постов
    op.create_table(
        'post_views',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('post_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('viewed_at', sa.DateTime(), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['post_id'], ['posts.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('post_id', 'user_id', name='_post_user_view_uc')
    )
    op.create_index(op.f('ix_post_views_id'), 'post_views', ['id'], unique=False)
    op.create_index(op.f('ix_post_views_post_id'), 'post_views', ['post_id'], unique=False)
    op.create_index(op.f('ix_post_views_user_id'), 'post_views', ['user_id'], unique=False)
    op.create_index(op.f('ix_post_views_viewed_at'), 'post_views', ['viewed_at'], unique=False)
    
    # Обновляем существующие посты - устанавливаем views_count = 0
    op.execute("UPDATE posts SET views_count = 0 WHERE views_count IS NULL")


def downgrade() -> None:
    op.drop_index(op.f('ix_post_views_viewed_at'), table_name='post_views')
    op.drop_index(op.f('ix_post_views_user_id'), table_name='post_views')
    op.drop_index(op.f('ix_post_views_post_id'), table_name='post_views')
    op.drop_index(op.f('ix_post_views_id'), table_name='post_views')
    op.drop_table('post_views')
    op.drop_column('posts', 'views_count')

