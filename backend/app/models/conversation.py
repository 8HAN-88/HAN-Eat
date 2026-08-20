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
    Text,
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
    avatar_url = Column(Text, nullable=True)
    created_by_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    only_admins_can_post = Column(Boolean, default=False, nullable=False)
    # Telegram-like Topics / Forum mode for groups.
    is_forum = Column(Boolean, default=False, nullable=False)
    join_by_request_enabled = Column(Boolean, default=False, nullable=False)
    slow_mode_seconds = Column(Integer, default=0, nullable=False)
    anti_flood_max_messages_per_minute = Column(Integer, default=0, nullable=False)
    # Telegram-like: restrict forwarding / saving content from this chat.
    protect_content = Column(Boolean, default=False, nullable=False)
    # Auto-delete messages older than this many seconds (0 = off).
    auto_delete_seconds = Column(Integer, default=0, nullable=False)
    # Telegram-like paid group: Stars subscription required to join.
    is_paid = Column(Boolean, default=False, nullable=False)
    monthly_price_stars = Column(Integer, default=0, nullable=False)
    invite_token = Column(String(96), nullable=True, unique=True, index=True)
    invite_token_updated_at = Column(DateTime, nullable=True)
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
    is_admin = Column(Boolean, default=False, nullable=False)
    can_manage_members = Column(Boolean, default=False, nullable=False)
    can_manage_posting_permissions = Column(Boolean, default=False, nullable=False)
    # Telegram-like granular admin rights (in addition to the two above).
    can_change_info = Column(Boolean, default=False, nullable=False)
    can_delete_messages = Column(Boolean, default=False, nullable=False)
    can_pin_messages = Column(Boolean, default=False, nullable=False)
    can_invite_users = Column(Boolean, default=False, nullable=False)
    can_manage_video_chats = Column(Boolean, default=False, nullable=False)
    send_restricted = Column(Boolean, default=False, nullable=False)
    send_restricted_until = Column(DateTime, nullable=True)
    send_restriction_reason = Column(Text, nullable=True)
    last_group_message_at = Column(DateTime, nullable=True)
    last_read_message_id = Column(Integer, nullable=True)
    # When the read cursor last advanced (Telegram Premium "read at").
    last_read_at = Column(DateTime, nullable=True)
    # Telegram-like: delivered cursor (gray ✓✓). Read implies delivered.
    last_delivered_message_id = Column(Integer, nullable=True)
    # Per-user clear history cursor: hide messages with id <= this value.
    history_cleared_before_id = Column(Integer, nullable=True)
    pinned = Column(Boolean, default=False, nullable=False)
    archived_at = Column(DateTime, nullable=True)
    muted_at = Column(DateTime, nullable=True)
    # Timed mute end (UTC naive). Null = muted forever while muted_at set.
    muted_until = Column(DateTime, nullable=True)
    # all | mentions | none — push fanout mode (Telegram mute variants).
    notify_mode = Column(String(16), nullable=False, default="all")
    # Built-in wallpaper style id (pattern/dusk/…).
    wallpaper_style = Column(String(32), nullable=True)
    # Custom wallpaper media URL (uploads); takes precedence over style when set.
    wallpaper_url = Column(String(512), nullable=True)
    # Outgoing bubble accent style id (mint/sky/…); null = default Telegram green.
    bubble_accent = Column(String(32), nullable=True)
    # Cursor for unread reactions on my messages (Telegram ❤ badge).
    reactions_seen_at = Column(DateTime, nullable=True)
    # Bot ReplyKeyboard state (Telegram-like, above composer).
    reply_keyboard_json = Column(String(4000), nullable=True)
    reply_keyboard_one_time = Column(Boolean, default=False, nullable=False)
    reply_keyboard_resize = Column(Boolean, default=True, nullable=False)
    reply_keyboard_placeholder = Column(String(64), nullable=True)
    auto_translate = Column(Boolean, default=False, nullable=False)
    joined_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint("conversation_id", "user_id", name="uq_conversation_member"),
    )


class GroupMemberBan(Base):
    __tablename__ = "group_member_bans"

    id = Column(Integer, primary_key=True, index=True)
    conversation_id = Column(
        Integer, ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    banned_by_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    banned = Column(Boolean, default=True, nullable=False, index=True)
    reason = Column(Text, nullable=True)
    banned_until = Column(DateTime, nullable=True, index=True)
    created_at = Column(DateTime, server_default=func.now(), index=True)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        UniqueConstraint("conversation_id", "user_id", name="uq_group_member_ban_pair"),
    )


class GroupJoinRequest(Base):
    __tablename__ = "group_join_requests"

    id = Column(Integer, primary_key=True, index=True)
    conversation_id = Column(
        Integer, ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    status = Column(String(20), nullable=False, default="pending", index=True)
    requested_at = Column(DateTime, server_default=func.now(), index=True)
    reviewed_at = Column(DateTime, nullable=True)
    reviewed_by_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )

    __table_args__ = (
        UniqueConstraint("conversation_id", "user_id", name="uq_group_join_request_pair"),
    )


class GroupInviteLink(Base):
    __tablename__ = "group_invite_links"

    id = Column(Integer, primary_key=True, index=True)
    conversation_id = Column(
        Integer, ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False, index=True
    )
    token = Column(String(96), nullable=False, unique=True, index=True)
    created_by_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    expires_at = Column(DateTime, nullable=True, index=True)
    max_uses = Column(Integer, nullable=True)
    uses_count = Column(Integer, nullable=False, default=0)
    revoked_at = Column(DateTime, nullable=True, index=True)
    created_at = Column(DateTime, server_default=func.now(), index=True)

    __table_args__ = (
        CheckConstraint("max_uses IS NULL OR max_uses > 0", name="check_group_invite_links_max_uses"),
    )


class ConversationPinnedMessage(Base):
    """Multi-pin slots per conversation (Telegram-like, cap enforced in service)."""

    __tablename__ = "conversation_pinned_messages"

    id = Column(Integer, primary_key=True, index=True)
    conversation_id = Column(
        Integer, ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False, index=True
    )
    message_id = Column(
        Integer, ForeignKey("messages.id", ondelete="CASCADE"), nullable=False, index=True
    )
    pinned_by_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    pinned_at = Column(DateTime, nullable=False)

    __table_args__ = (
        UniqueConstraint(
            "conversation_id", "message_id", name="uq_conversation_pinned_message"
        ),
    )


class ConversationDraft(Base):
    """Per-user cloud composer draft for a conversation."""

    __tablename__ = "conversation_drafts"

    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    conversation_id = Column(
        Integer, ForeignKey("conversations.id", ondelete="CASCADE"), primary_key=True
    )
    text = Column(String(4000), nullable=False, default="")
    reply_to_message_id = Column(
        Integer, ForeignKey("messages.id", ondelete="SET NULL"), nullable=True
    )
    updated_at = Column(DateTime, nullable=False, server_default=func.now())


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
    # Forward attribution (Telegram «Переслано от…»)
    forward_from_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    forward_from_name = Column(String(120), nullable=True)
    forwarded_from_message_id = Column(
        Integer, ForeignKey("messages.id", ondelete="SET NULL"), nullable=True
    )
    created_at = Column(DateTime, server_default=func.now(), index=True)
    edited_at = Column(DateTime, nullable=True)
    deleted_at = Column(DateTime, nullable=True)
    # When true, clients should not render a webpage preview for URLs in content.
    disable_webpage_preview = Column(Boolean, default=False, nullable=False)
    # Shared client/server id for multi-media albums (Telegram media_group).
    media_group_id = Column(String(64), nullable=True, index=True)
    # Telegram media spoiler: blur until tapped (image/video).
    has_spoiler = Column(Boolean, default=False, nullable=False)
    # Telegram Stars paid media: locked until unlock purchase.
    is_paid = Column(Boolean, default=False, nullable=False, index=True)
    price_stars = Column(Integer, default=0, nullable=False)
    # Telegram-like fullscreen send effect (confetti, hearts, …).
    effect_id = Column(String(32), nullable=True)
    # Forum topic (null = General / pre-forum messages).
    topic_id = Column(
        Integer, ForeignKey("forum_topics.id", ondelete="SET NULL"), nullable=True, index=True
    )
    # Group admin posts as the group (Telegram anonymous admin).
    is_anonymous = Column(Boolean, default=False, nullable=False)
    # Telegram Premium voice-to-text.
    transcription = Column(Text, nullable=True)


class ScheduledMessage(Base):
    __tablename__ = "scheduled_messages"

    id = Column(Integer, primary_key=True, index=True)
    conversation_id = Column(
        Integer, ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False, index=True
    )
    sender_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    type = Column(String(20), nullable=False, default="text")
    content = Column(String(4000), nullable=False, default="")
    media_url = Column(String(512), nullable=True)
    reply_to_message_id = Column(Integer, ForeignKey("messages.id", ondelete="SET NULL"), nullable=True)
    client_message_id = Column(String(64), nullable=True)
    inline_keyboard_json = Column(String(4000), nullable=True)
    send_at = Column(DateTime, nullable=False, index=True)
    deliver_when_online = Column(Boolean, nullable=False, default=False)
    silent = Column(Boolean, nullable=False, default=False)
    disable_webpage_preview = Column(Boolean, nullable=False, default=False)
    media_group_id = Column(String(64), nullable=True)
    has_spoiler = Column(Boolean, nullable=False, default=False)
    # Telegram-like send effect applied when the scheduled message is dispatched.
    effect_id = Column(String(32), nullable=True)
    # Forum topic for groups with Topics enabled.
    topic_id = Column(
        Integer, ForeignKey("forum_topics.id", ondelete="SET NULL"), nullable=True, index=True
    )
    target_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    status = Column(String(16), nullable=False, default="pending", index=True)
    sent_message_id = Column(Integer, ForeignKey("messages.id", ondelete="SET NULL"), nullable=True)
    sent_at = Column(DateTime, nullable=True)
    error_text = Column(String(120), nullable=True)
    created_at = Column(DateTime, server_default=func.now(), index=True)
    canceled_at = Column(DateTime, nullable=True)


class MessageReaction(Base):
    __tablename__ = "message_reactions"

    id = Column(Integer, primary_key=True, index=True)
    message_id = Column(
        Integer, ForeignKey("messages.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    emoji = Column(String(32), nullable=False)
    # Telegram paid reactions: Stars spent on this reaction (0 = free).
    stars_amount = Column(Integer, default=0, nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint("message_id", "user_id", name="uq_message_reaction_user"),
    )


class MessageHide(Base):
    """Per-user hide (Telegram «удалить у меня»)."""

    __tablename__ = "message_hides"

    id = Column(Integer, primary_key=True, index=True)
    message_id = Column(
        Integer, ForeignKey("messages.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint("message_id", "user_id", name="uq_message_hide_user"),
    )


class MessageEditHistory(Base):
    """Previous message bodies captured before each edit."""

    __tablename__ = "message_edit_history"

    id = Column(Integer, primary_key=True, index=True)
    message_id = Column(
        Integer, ForeignKey("messages.id", ondelete="CASCADE"), nullable=False, index=True
    )
    editor_id = Column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    previous_content = Column(String(4000), nullable=False, default="")
    edited_at = Column(DateTime, nullable=False, index=True)


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
