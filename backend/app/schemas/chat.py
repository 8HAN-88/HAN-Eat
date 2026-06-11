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

    class Config:
        from_attributes = True


class MessageResponse(BaseModel):
    id: int
    conversation_id: int
    sender_id: int
    sender_name: Optional[str] = None
    type: str
    content: str
    media_url: Optional[str] = None
    reply_to_message_id: Optional[int] = None
    created_at: datetime
    edited_at: Optional[datetime] = None
    is_mine: bool = False
    is_read: bool = False
    reactions: List["MessageReactionSummary"] = []

    class Config:
        from_attributes = True


class MessageReactionSummary(BaseModel):
    emoji: str
    count: int
    reacted_by_me: bool = False


class ConversationResponse(BaseModel):
    id: int
    type: str
    peer: Optional[ChatUserBrief] = None
    title: Optional[str] = None
    member_count: int = 0
    members_preview: List[ChatUserBrief] = []
    last_message: Optional[MessageResponse] = None
    unread_count: int = 0
    updated_at: datetime
    pinned: bool = False
    archived: bool = False
    muted: bool = False
    created_by_user_id: Optional[int] = None

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


class EditMessageRequest(BaseModel):
    content: str = Field(..., min_length=1, max_length=4000)


class MessageReactionRequest(BaseModel):
    emoji: str = Field(..., min_length=1, max_length=16)


class PinMessageRequest(BaseModel):
    pinned: bool = True


class SendMessageRequest(BaseModel):
    type: str = Field(default="text", pattern="^(text|image|voice|file|video)$")
    content: str = Field(default="", max_length=4000)
    media_url: Optional[str] = Field(default=None, max_length=512)
    reply_to_message_id: Optional[int] = None


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


class PinChatRequest(BaseModel):
    pinned: bool = True


class MuteChatRequest(BaseModel):
    muted: bool = True


class UpdateGroupChatRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=120)


class AddGroupMembersRequest(BaseModel):
    user_ids: List[int] = Field(..., min_length=1)


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
