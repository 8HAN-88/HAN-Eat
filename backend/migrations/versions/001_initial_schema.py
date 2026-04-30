"""Initial schema

Revision ID: 001_initial
Revises: 
Create Date: 2025-01-XX

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '001_initial'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Users
    op.create_table(
        'users',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('email', sa.String(length=255), nullable=False),
        sa.Column('password_hash', sa.String(length=255), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('username', sa.String(length=100), nullable=True),
        sa.Column('avatar_url', sa.Text(), nullable=True),
        sa.Column('bio', sa.Text(), nullable=True),
        sa.Column('is_private', sa.Boolean(), nullable=True),
        sa.Column('is_verified', sa.Boolean(), nullable=True),
        sa.Column('subscription_type', sa.String(length=20), nullable=True),
        sa.Column('subscription_expires_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()'), nullable=True),
        sa.Column('updated_at', sa.DateTime(), server_default=sa.text('now()'), nullable=True),
        sa.Column('deleted_at', sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_users_email'), 'users', ['email'], unique=True)
    op.create_index(op.f('ix_users_id'), 'users', ['id'], unique=False)
    op.create_index(op.f('ix_users_username'), 'users', ['username'], unique=True)
    
    # Communities
    op.create_table(
        'communities',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('slug', sa.String(length=100), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('cover_url', sa.Text(), nullable=True),
        sa.Column('avatar_url', sa.Text(), nullable=True),
        sa.Column('admin_user_id', sa.Integer(), nullable=False),
        sa.Column('is_public', sa.Boolean(), nullable=True),
        sa.Column('members_count', sa.Integer(), nullable=True),
        sa.Column('posts_count', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()'), nullable=True),
        sa.Column('updated_at', sa.DateTime(), server_default=sa.text('now()'), nullable=True),
        sa.ForeignKeyConstraint(['admin_user_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('slug')
    )
    op.create_index(op.f('ix_communities_admin_user_id'), 'communities', ['admin_user_id'], unique=False)
    op.create_index(op.f('ix_communities_id'), 'communities', ['id'], unique=False)
    op.create_index(op.f('ix_communities_slug'), 'communities', ['slug'], unique=True)
    
    # Posts
    op.create_table(
        'posts',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('community_id', sa.Integer(), nullable=True),
        sa.Column('type', sa.String(length=20), nullable=False),
        sa.Column('title', sa.String(length=500), nullable=True),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('body', postgresql.JSON(astext_type=sa.Text()), nullable=True),
        sa.Column('status', sa.String(length=20), nullable=True),
        sa.Column('visibility', sa.String(length=20), nullable=True),
        sa.Column('publish_to', postgresql.ARRAY(sa.String()), nullable=True),
        sa.Column('tags', postgresql.ARRAY(sa.String()), nullable=True),
        sa.Column('location_name', sa.String(length=255), nullable=True),
        sa.Column('location_lat', sa.String(), nullable=True),
        sa.Column('location_lng', sa.String(), nullable=True),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()'), nullable=True),
        sa.Column('updated_at', sa.DateTime(), server_default=sa.text('now()'), nullable=True),
        sa.Column('published_at', sa.DateTime(), nullable=True),
        sa.Column('deleted_at', sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(['community_id'], ['communities.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_posts_community_id'), 'posts', ['community_id'], unique=False)
    op.create_index(op.f('ix_posts_created_at'), 'posts', ['created_at'], unique=False)
    op.create_index(op.f('ix_posts_id'), 'posts', ['id'], unique=False)
    op.create_index(op.f('ix_posts_published_at'), 'posts', ['published_at'], unique=False)
    op.create_index(op.f('ix_posts_status'), 'posts', ['status'], unique=False)
    op.create_index(op.f('ix_posts_type'), 'posts', ['type'], unique=False)
    op.create_index(op.f('ix_posts_user_id'), 'posts', ['user_id'], unique=False)
    
    # Followers
    op.create_table(
        'followers',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('follower_id', sa.Integer(), nullable=False),
        sa.Column('followee_id', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()'), nullable=True),
        sa.CheckConstraint('follower_id != followee_id', name='check_no_self_follow'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_followers_followee_id'), 'followers', ['followee_id'], unique=False)
    op.create_index(op.f('ix_followers_follower_id'), 'followers', ['follower_id'], unique=False)
    op.create_index(op.f('ix_followers_id'), 'followers', ['id'], unique=False)
    op.create_unique_constraint('uq_followers_follower_followee', 'followers', ['follower_id', 'followee_id'])
    
    # Community Members
    op.create_table(
        'community_members',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('community_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('role', sa.String(length=20), nullable=True),
        sa.Column('joined_at', sa.DateTime(), server_default=sa.text('now()'), nullable=True),
        sa.ForeignKeyConstraint(['community_id'], ['communities.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('community_id', 'user_id')
    )
    op.create_index(op.f('ix_community_members_community_id'), 'community_members', ['community_id'], unique=False)
    op.create_index(op.f('ix_community_members_id'), 'community_members', ['id'], unique=False)
    op.create_index(op.f('ix_community_members_user_id'), 'community_members', ['user_id'], unique=False)
    
    # Saved Posts
    op.create_table(
        'saved_posts',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('post_id', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()'), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'post_id')
    )
    op.create_index(op.f('ix_saved_posts_id'), 'saved_posts', ['id'], unique=False)
    op.create_index(op.f('ix_saved_posts_post_id'), 'saved_posts', ['post_id'], unique=False)
    op.create_index(op.f('ix_saved_posts_user_id'), 'saved_posts', ['user_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_saved_posts_user_id'), table_name='saved_posts')
    op.drop_index(op.f('ix_saved_posts_post_id'), table_name='saved_posts')
    op.drop_index(op.f('ix_saved_posts_id'), table_name='saved_posts')
    op.drop_table('saved_posts')
    
    op.drop_index(op.f('ix_community_members_user_id'), table_name='community_members')
    op.drop_index(op.f('ix_community_members_id'), table_name='community_members')
    op.drop_index(op.f('ix_community_members_community_id'), table_name='community_members')
    op.drop_table('community_members')
    
    op.drop_constraint('uq_followers_follower_followee', 'followers', type_='unique')
    op.drop_index(op.f('ix_followers_id'), table_name='followers')
    op.drop_index(op.f('ix_followers_followee_id'), table_name='followers')
    op.drop_index(op.f('ix_followers_follower_id'), table_name='followers')
    op.drop_table('followers')
    
    op.drop_index(op.f('ix_posts_user_id'), table_name='posts')
    op.drop_index(op.f('ix_posts_type'), table_name='posts')
    op.drop_index(op.f('ix_posts_status'), table_name='posts')
    op.drop_index(op.f('ix_posts_published_at'), table_name='posts')
    op.drop_index(op.f('ix_posts_id'), table_name='posts')
    op.drop_index(op.f('ix_posts_created_at'), table_name='posts')
    op.drop_index(op.f('ix_posts_community_id'), table_name='posts')
    op.drop_table('posts')
    
    op.drop_index(op.f('ix_communities_slug'), table_name='communities')
    op.drop_index(op.f('ix_communities_id'), table_name='communities')
    op.drop_index(op.f('ix_communities_admin_user_id'), table_name='communities')
    op.drop_table('communities')
    
    op.drop_index(op.f('ix_users_username'), table_name='users')
    op.drop_index(op.f('ix_users_id'), table_name='users')
    op.drop_index(op.f('ix_users_email'), table_name='users')
    op.drop_table('users')

