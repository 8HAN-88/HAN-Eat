"""Модели личных чатов (1-on-1)."""
from sqlalchemy import (
    Column,
    Integer,
    String,
    DateTime,
    ForeignKey,
    Boolean,
    UniqueConstraint,
    CheckConstraint,
)
from sqlalchemy.sql import func
from app.core.database import Base


class Conversation(Base):
    __tablename__ = "conversations"

    id = Column(Integer, primary_key=True, index=True)
    type = Column(String(20), nullable=False, default="direct", index=True)
    # Для direct: canonical pair (меньший id, больший id) — уникальная пара.
    direct_user_low_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True)
    direct_user_high_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True)
    title = Column(String(120), nullable=True)
    created_by_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    pinned_message_id = Column(Integer, ForeignKey("messages.id", ondelete="SET NULL"), nullable=True)
    pinned_at = Column(DateTime, nullable=True)
    pinned_by_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now(), index=True)

    __table_args__ = (
        UniqueConstraint("direct_user_low_id", "direct_user_high_id", name="uq_direct_conversation_pair"),
        CheckConstraint("direct_user_low_id < direct_user_high_id", name="check_direct_pair_order"),
    )


class ConversationMember(Base):
    __tablename__ = "conversation_members"

    id = Column(Integer, primary_key=True, index=True)
    conversation_id = Column(
        Integer, ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    last_read_message_id = Column(Integer, nullable=True)
    pinned = Column(Boolean, default=False, nullable=False)
    archived_at = Column(DateTime, nullable=True)
    muted_at = Column(DateTime, nullable=True)
    joined_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint("conversation_id", "user_id", name="uq_conversation_member"),
    )


class Message(Base):
    __tablename__ = "messages"

    id = Column(Integer, primary_key=True, index=True)
    conversation_id = Column(
        Integer, ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False, index=True
    )
    sender_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    type = Column(String(20), nullable=False, default="text")  # text | image
    content = Column(String(4000), nullable=False, default="")
    media_url = Column(String(512), nullable=True)
    reply_to_message_id = Column(Integer, ForeignKey("messages.id", ondelete="SET NULL"), nullable=True)
    client_message_id = Column(String(64), nullable=True)
    inline_keyboard_json = Column(String(4000), nullable=True)
    created_at = Column(DateTime, server_default=func.now(), index=True)
    edited_at = Column(DateTime, nullable=True)
    deleted_at = Column(DateTime, nullable=True)


class MessageReaction(Base):
    __tablename__ = "message_reactions"

    id = Column(Integer, primary_key=True, index=True)
    message_id = Column(
        Integer, ForeignKey("messages.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    emoji = Column(String(16), nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint("message_id", "user_id", name="uq_message_reaction_user"),
    )


class Contact(Base):
    __tablename__ = "contacts"

    id = Column(Integer, primary_key=True, index=True)
    owner_user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    contact_user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint("owner_user_id", "contact_user_id", name="uq_contact_pair"),
        CheckConstraint("owner_user_id != contact_user_id", name="check_no_self_contact"),
    )
