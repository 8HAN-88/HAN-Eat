"""Add subscriptions table and update users

Revision ID: 008_subscriptions
Revises: 007_notifications
Create Date: 2025-01-XX

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '008_subscriptions'
down_revision = '007_notifications'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Добавляем поля подписки в users (если их еще нет)
    # Проверяем, существуют ли колонки
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    columns = [col['name'] for col in inspector.get_columns('users')]
    
    if 'subscription_type' not in columns:
        op.add_column('users', sa.Column('subscription_type', sa.String(length=20), nullable=True, server_default='free'))
    if 'subscription_expires_at' not in columns:
        op.add_column('users', sa.Column('subscription_expires_at', sa.DateTime(), nullable=True))
    
    # Создаем таблицу subscriptions
    op.create_table(
        'subscriptions',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('plan', sa.String(length=20), nullable=False),
        sa.Column('status', sa.String(length=20), nullable=False),
        sa.Column('payment_provider', sa.String(length=20), nullable=True),
        sa.Column('payment_provider_subscription_id', sa.String(length=255), nullable=True),
        sa.Column('amount', sa.Numeric(precision=10, scale=2), nullable=False),
        sa.Column('currency', sa.String(length=3), nullable=True),
        sa.Column('started_at', sa.DateTime(), server_default=sa.text('now()'), nullable=False),
        sa.Column('expires_at', sa.DateTime(), nullable=True),
        sa.Column('cancelled_at', sa.DateTime(), nullable=True),
        sa.Column('auto_renew', sa.Boolean(), nullable=True),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()'), nullable=True),
        sa.Column('updated_at', sa.DateTime(), server_default=sa.text('now()'), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_subscriptions_id'), 'subscriptions', ['id'], unique=False)
    op.create_index(op.f('ix_subscriptions_user_id'), 'subscriptions', ['user_id'], unique=False)
    op.create_index(op.f('ix_subscriptions_status'), 'subscriptions', ['status'], unique=False)
    op.create_index(op.f('ix_subscriptions_payment_provider_subscription_id'), 'subscriptions', ['payment_provider_subscription_id'], unique=False)
    op.create_index(op.f('ix_subscriptions_expires_at'), 'subscriptions', ['expires_at'], unique=False)
    op.create_index(op.f('ix_subscriptions_created_at'), 'subscriptions', ['created_at'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_subscriptions_created_at'), table_name='subscriptions')
    op.drop_index(op.f('ix_subscriptions_expires_at'), table_name='subscriptions')
    op.drop_index(op.f('ix_subscriptions_payment_provider_subscription_id'), table_name='subscriptions')
    op.drop_index(op.f('ix_subscriptions_status'), table_name='subscriptions')
    op.drop_index(op.f('ix_subscriptions_user_id'), table_name='subscriptions')
    op.drop_index(op.f('ix_subscriptions_id'), table_name='subscriptions')
    op.drop_table('subscriptions')
    
    # Удаляем колонки из users (опционально, можно оставить для обратной совместимости)
    # op.drop_column('users', 'subscription_expires_at')
    # op.drop_column('users', 'subscription_type')

