"""
Alembic environment configuration
"""
from logging.config import fileConfig
from sqlalchemy import engine_from_config, inspect, pool, text
from alembic import context
import os
import sys

# Добавляем путь к app
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from app.core.config import settings
from app.core.database import Base
# Импортируем все модели для autogenerate
from app.models.user import User
from app.models.auth_token import AuthToken
from app.models.post import Post
from app.models.community import Channel
from app.models.follower import Follower
from app.models.community_member import ChannelMember
from app.models.saved_post import SavedPost
from app.models.like import Like
from app.models.comment import Comment
from app.models.repost import Repost
from app.models.moderation_queue import ModerationQueue
from app.models.analytics_event import AnalyticsEvent
from app.models.ai_meal_plan_record import AiMealPlanRecord
from app.models.notification import Notification
from app.models.conversation import Conversation, ConversationMember, Message, Contact
from app.models.subscription import Subscription
from app.models.support_ticket import SupportTicket
from app.models.notification_preferences import NotificationPreferences
from app.models.video_processing import VideoProcessing
from app.models.image_processing import ImageProcessing

# this is the Alembic Config object
config = context.config

# Устанавливаем URL БД из настроек
config.set_main_option("sqlalchemy.url", settings.DATABASE_URL)

# Interpret the config file for Python logging.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# add your model's MetaData object here for 'autogenerate' support
target_metadata = Base.metadata


def _ensure_wide_alembic_version(connection) -> None:
    """Revision ids in this repo exceed Alembic's default VARCHAR(32)."""
    inspector = inspect(connection)
    tables = set(inspector.get_table_names())
    if "alembic_version" not in tables:
        connection.execute(
            text(
                "CREATE TABLE alembic_version ("
                "version_num VARCHAR(128) NOT NULL"
                ")"
            )
        )
        return
    if connection.dialect.name != "postgresql":
        return
    # Widen when still on Alembic's default 32-char column.
    connection.execute(
        text(
            "ALTER TABLE alembic_version "
            "ALTER COLUMN version_num TYPE VARCHAR(128)"
        )
    )


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        _ensure_wide_alembic_version(connection)
        connection.commit()
        context.configure(
            connection=connection, target_metadata=target_metadata
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()

