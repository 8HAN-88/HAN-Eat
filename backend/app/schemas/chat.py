"""Схемы API чатов и контактов."""
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field


class ChatUserBrief(BaseModel):
    id: int
    name: Optional[str] = None
    username: Optional[str] = None
    avatar_url: Optional[str] = None
    last_seen_at: Optional[datetime] = None
    is_bot: bool = False
    is_group_admin: bool = False
    is_group_creator: bool = False
    can_manage_members: bool = False
    can_manage_posting_permissions: bool = False
    send_restricted: bool = False
    send_restricted_until: Optional[datetime] = None
    send_restriction_reason: Optional[str] = None

    class Config:
        from_attributes = True


class ChatBotCommandItem(BaseModel):
    command: str
    description: str = ""


class ChatBotCommandsResponse(BaseModel):
    bot_id: int
    bot_username: Optional[str] = None
    items: List[ChatBotCommandItem] = []


class MessageResponse(BaseModel):
    id: int
    conversation_id: int
    sender_id: int
    sender_name: Optional[str] = None
    type: str
    content: str
    media_url: Optional[str] = None
    reply_to_message_id: Optional[int] = None
    forward_from_user_id: Optional[int] = None
    forward_from_name: Optional[str] = None
    forwarded_from_message_id: Optional[int] = None
    # Source conversation of the original message (for «go to original»).
    forwarded_from_conversation_id: Optional[int] = None
    created_at: datetime
    edited_at: Optional[datetime] = None
    inline_keyboard: Optional[List[List["InlineKeyboardButton"]]] = None
    is_mine: bool = False
    is_delivered: bool = False
    is_read: bool = False
    # Group: how many other members have read up to this message (mine only).
    read_count: int = 0
    disable_webpage_preview: bool = False
    reactions: List["MessageReactionSummary"] = []

    class Config:
        from_attributes = True


class ForwardMessageRequest(BaseModel):
    source_conversation_id: int
    message_id: int
    as_copy: bool = False


class MessageReaderItem(BaseModel):
    user: ChatUserBrief


class MessageReadersResponse(BaseModel):
    items: List[MessageReaderItem]
    reader_count: int = 0
    other_member_count: int = 0


class MessageReactionUserItem(BaseModel):
    emoji: str
    user: ChatUserBrief


class MessageReactionsDetailResponse(BaseModel):
    items: List[MessageReactionUserItem]
    reaction_count: int = 0


class MessageReactionSummary(BaseModel):
    emoji: str
    count: int
    reacted_by_me: bool = False


class ConversationResponse(BaseModel):
    id: int
    type: str
    peer: Optional[ChatUserBrief] = None
    title: Optional[str] = None
    avatar_url: Optional[str] = None
    member_count: int = 0
    pending_join_requests_count: int = 0
    members_preview: List[ChatUserBrief] = []
    last_message: Optional[MessageResponse] = None
    unread_count: int = 0
    unread_mentions_count: int = 0
    unread_reactions_count: int = 0
    updated_at: datetime
    pinned: bool = False
    archived: bool = False
    muted: bool = False
    muted_until: Optional[datetime] = None
    wallpaper_style: Optional[str] = None
    bubble_accent: Optional[str] = None
    created_by_user_id: Optional[int] = None
    only_admins_can_post: bool = False
    join_by_request_enabled: bool = False
    slow_mode_seconds: int = 0
    anti_flood_max_messages_per_minute: int = 0
    protect_content: bool = False
    auto_delete_seconds: int = 0
    am_i_group_admin: bool = False
    am_i_can_manage_members: bool = False
    am_i_can_manage_posting_permissions: bool = False
    am_i_send_restricted: bool = False
    am_i_send_restricted_until: Optional[datetime] = None
    am_i_send_restriction_reason: Optional[str] = None
    peer_blocked_by_me: bool = False

    class Config:
        from_attributes = True


class ConversationListResponse(BaseModel):
    items: List[ConversationResponse]
    total_unread: int = 0


class MessageListResponse(BaseModel):
    items: List[MessageResponse]
    has_more: bool = False
    next_cursor: Optional[int] = None
    pinned_message: Optional[MessageResponse] = None
    pinned_messages: List[MessageResponse] = []


class ConversationDraftRequest(BaseModel):
    text: str = Field(default="", max_length=4000)
    reply_to_message_id: Optional[int] = None


class ConversationDraftResponse(BaseModel):
    conversation_id: int
    text: str = ""
    reply_to_message_id: Optional[int] = None
    updated_at: datetime


class ConversationDraftListResponse(BaseModel):
    items: List[ConversationDraftResponse]


class MessageSearchItem(BaseModel):
    message: MessageResponse
    conversation: ConversationResponse
    snippet: str = ""


class MessageSearchResponse(BaseModel):
    items: List[MessageSearchItem]


class EditMessageRequest(BaseModel):
    # Empty allowed for clearing image/video/file captions.
    content: str = Field(default="", max_length=4000)


class MessageReactionRequest(BaseModel):
    emoji: str = Field(..., min_length=1, max_length=16)


class TypingActivityRequest(BaseModel):
    """Telegram-like activity: typing or recording a voice message."""

    activity: str = Field(default="typing", pattern="^(typing|recording)$")


class PinMessageRequest(BaseModel):
    pinned: bool = True


class SendMessageRequest(BaseModel):
    type: str = Field(
        default="text",
        pattern="^(text|image|voice|file|video|video_note|poll|sticker|location)$",
    )
    content: str = Field(default="", max_length=4000)
    media_url: Optional[str] = Field(default=None, max_length=512)
    reply_to_message_id: Optional[int] = None
    client_message_id: Optional[str] = Field(default=None, max_length=64)
    poll_question: Optional[str] = Field(default=None, max_length=300)
    poll_description: Optional[str] = Field(default=None, max_length=500)
    poll_options: Optional[List[str]] = None
    poll_settings: Optional[dict] = None
    inline_keyboard: Optional[List[List["InlineKeyboardButton"]]] = None
    silent: bool = False
    disable_webpage_preview: bool = False


class ScheduleMessageRequest(BaseModel):
    type: str = Field(
        default="text",
        pattern="^(text|image|voice|file|video|video_note|poll|sticker|location)$",
    )
    content: str = Field(default="", max_length=4000)
    media_url: Optional[str] = Field(default=None, max_length=512)
    reply_to_message_id: Optional[int] = None
    client_message_id: Optional[str] = Field(default=None, max_length=64)
    poll_question: Optional[str] = Field(default=None, max_length=300)
    poll_description: Optional[str] = Field(default=None, max_length=500)
    poll_options: Optional[List[str]] = None
    poll_settings: Optional[dict] = None
    inline_keyboard: Optional[List[List["InlineKeyboardButton"]]] = None
    send_at: Optional[datetime] = None
    send_when_online: bool = False


class ScheduledMessageResponse(BaseModel):
    id: int
    conversation_id: int
    sender_id: int
    type: str
    content: str
    media_url: Optional[str] = None
    reply_to_message_id: Optional[int] = None
    send_at: datetime
    send_when_online: bool = False
    status: str
    created_at: datetime

    class Config:
        from_attributes = True


class ScheduledMessageListResponse(BaseModel):
    items: List[ScheduledMessageResponse]


class RescheduleMessageRequest(BaseModel):
    send_at: Optional[datetime] = None
    content: Optional[str] = Field(default=None, min_length=1, max_length=4000)


class InlineKeyboardButton(BaseModel):
    text: str = Field(..., min_length=1, max_length=64)
    callback_data: Optional[str] = Field(default=None, max_length=128)
    url: Optional[str] = Field(default=None, max_length=512)
    callback_text: Optional[str] = Field(default=None, max_length=300)


class CallbackQueryRequest(BaseModel):
    data: str = Field(..., min_length=1, max_length=128)


class ChatPollVoteRequest(BaseModel):
    option_index: int = Field(..., ge=0, le=11)


class ChatPollAddOptionRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=120)


class DirectChatRequest(BaseModel):
    user_id: int


class CreateGroupChatRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=120)
    member_ids: List[int] = Field(..., min_length=1)


class ArchiveChatRequest(BaseModel):
    archived: bool = True


class ConversationMembersResponse(BaseModel):
    items: List[ChatUserBrief]


class MarkReadRequest(BaseModel):
    message_id: int


class MarkDeliveredRequest(BaseModel):
    message_id: int


class PinChatRequest(BaseModel):
    pinned: bool = True


class MuteChatRequest(BaseModel):
    muted: bool = True
    muted_until: Optional[datetime] = None


class WallpaperStyleRequest(BaseModel):
    style: Optional[str] = Field(default=None, max_length=32)
    apply_to_all: bool = False


class BubbleAccentRequest(BaseModel):
    accent: Optional[str] = Field(default=None, max_length=32)
    apply_to_all: bool = False


class UpdateGroupChatRequest(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=120)
    avatar_url: Optional[str] = Field(None, max_length=512)
    only_admins_can_post: Optional[bool] = None
    join_by_request_enabled: Optional[bool] = None
    slow_mode_seconds: Optional[int] = Field(default=None, ge=0, le=3600)
    anti_flood_max_messages_per_minute: Optional[int] = Field(
        default=None, ge=0, le=120
    )
    protect_content: Optional[bool] = None
    auto_delete_seconds: Optional[int] = Field(default=None, ge=0, le=2592000)


class TranslateTextRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=4000)
    target_lang: str = Field(default="ru", min_length=2, max_length=8)


class TranslateTextResponse(BaseModel):
    text: str
    translated: str
    target_lang: str


class MessageEditHistoryItem(BaseModel):
    content: str
    edited_at: datetime
    editor_id: Optional[int] = None


class MessageEditHistoryResponse(BaseModel):
    items: List[MessageEditHistoryItem] = []
    current_content: str = ""
    message_type: str = "text"


class AddGroupMembersRequest(BaseModel):
    user_ids: List[int] = Field(..., min_length=1)


class GroupMemberAdminRequest(BaseModel):
    is_admin: bool = True


class GroupMemberPermissionsRequest(BaseModel):
    can_manage_members: bool = False
    can_manage_posting_permissions: bool = False


class GroupMemberSendRestrictionRequest(BaseModel):
    send_restricted: bool = True
    send_restricted_until: Optional[datetime] = None
    reason: Optional[str] = Field(default=None, max_length=240)


class GroupMemberBanRequest(BaseModel):
    reason: Optional[str] = Field(default=None, max_length=240)
    banned_until: Optional[datetime] = None


class GroupMemberBanResponse(BaseModel):
    user: ChatUserBrief
    reason: Optional[str] = None
    banned_until: Optional[datetime] = None
    banned_at: datetime


class GroupMemberBanListResponse(BaseModel):
    items: List[GroupMemberBanResponse]


class GroupInviteLinkCreateRequest(BaseModel):
    expires_at: Optional[datetime] = None
    max_uses: Optional[int] = Field(default=None, ge=1, le=100000)


class GroupInviteLinkResponse(BaseModel):
    id: int
    token: str
    invite_link: str
    expires_at: Optional[datetime] = None
    max_uses: Optional[int] = None
    uses_count: int = 0
    revoked_at: Optional[datetime] = None
    created_at: datetime


class GroupInviteLinkListResponse(BaseModel):
    items: List[GroupInviteLinkResponse]


class GroupJoinRequestResponse(BaseModel):
    id: int
    user: ChatUserBrief
    status: str
    requested_at: datetime


class GroupJoinRequestListResponse(BaseModel):
    items: List[GroupJoinRequestResponse]


class GroupJoinRequestReviewRequest(BaseModel):
    approve: bool = True


class JoinByInviteResponse(BaseModel):
    status: str  # joined | requested
    conversation: Optional[ConversationResponse] = None


class JoinRequestsInboxItemResponse(BaseModel):
    id: int
    conversation: ConversationResponse
    user: ChatUserBrief
    status: str
    requested_at: datetime


class JoinRequestsInboxResponse(BaseModel):
    items: List[JoinRequestsInboxItemResponse]


class GroupModerationLogItemResponse(BaseModel):
    id: int
    action: str
    text: str
    created_at: datetime
    actor: Optional[ChatUserBrief] = None


class GroupModerationLogResponse(BaseModel):
    items: List[GroupModerationLogItemResponse]


class ContactResponse(BaseModel):
    id: int
    user: ChatUserBrief
    created_at: datetime

    class Config:
        from_attributes = True


class ContactListResponse(BaseModel):
    items: List[ContactResponse]


class AddContactRequest(BaseModel):
    user_id: int


class UserSearchItem(BaseModel):
    id: int
    name: Optional[str] = None
    username: Optional[str] = None
    avatar_url: Optional[str] = None
    is_contact: bool = False

    class Config:
        from_attributes = True


class UserSearchResponse(BaseModel):
    items: List[UserSearchItem]


class PhoneSyncRequest(BaseModel):
    phone_hashes: List[str] = Field(..., max_length=500)


class PhoneContactMatchItem(BaseModel):
    id: int
    name: Optional[str] = None
    username: Optional[str] = None
    avatar_url: Optional[str] = None
    is_contact: bool = False
    phone_hash: Optional[str] = None

    class Config:
        from_attributes = True


class PhoneSyncResponse(BaseModel):
    items: List[PhoneContactMatchItem]


class ChatFolderResponse(BaseModel):
    id: int
    name: str
    icon: Optional[str] = None
    position: int = 0
    conversation_ids: List[int] = []
    channel_ids: List[int] = []
    filters: dict = Field(default_factory=dict)


class ChatFolderListResponse(BaseModel):
    items: List[ChatFolderResponse]


class CreateChatFolderRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=64)
    icon: Optional[str] = Field(None, max_length=8)
    conversation_ids: List[int] = []
    channel_ids: List[int] = []
    filters: dict = Field(default_factory=dict)


class UpdateChatFolderRequest(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=64)
    icon: Optional[str] = Field(None, max_length=8)
    conversation_ids: Optional[List[int]] = None
    channel_ids: Optional[List[int]] = None
    filters: Optional[dict] = None


class ReorderChatFoldersRequest(BaseModel):
    folder_ids: List[int] = Field(..., min_length=1)


class ChatFolderItemRequest(BaseModel):
    conversation_id: Optional[int] = None
    channel_id: Optional[int] = None


MessageResponse.model_rebuild()
SendMessageRequest.model_rebuild()
ScheduleMessageRequest.model_rebuild()
RescheduleMessageRequest.model_rebuild()

