"""API личных чатов и контактов."""
import asyncio
import json
from datetime import datetime
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import StreamingResponse
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user_required
from app.core.config import settings
from app.core.database import get_db
from app.models.user import User
from app.schemas.chat import (
    AddContactRequest,
    AddGroupMembersRequest,
    ArchiveChatRequest,
    ContactListResponse,
    ContactResponse,
    ConversationListResponse,
    ConversationMembersResponse,
    ConversationResponse,
    ChatUserBrief,
    ChatBotCommandItem,
    ChatBotCommandsResponse,
    CreateGroupChatRequest,
    CreateChatFolderRequest,
    ChatFolderItemRequest,
    ChatFolderListResponse,
    ChatFolderResponse,
    ReorderChatFoldersRequest,
    DirectChatRequest,
    EditMessageRequest,
    ForwardMessageRequest,
    MessageEditHistoryItem,
    MessageEditHistoryResponse,
    TranslateTextRequest,
    TranslateTextResponse,
    MessageReaderItem,
    MessageReadersResponse,
    MessageReactionUserItem,
    MessageReactionsDetailResponse,
    RescheduleMessageRequest,
    ScheduledMessageListResponse,
    ScheduledMessageResponse,
    ScheduleMessageRequest,
    MarkDeliveredRequest,
    MarkReadRequest,
    MessageReactionRequest,
    MessageReactionSummary,
    MessageSearchItem,
    MessageSearchResponse,
    MuteChatRequest,
    PinChatRequest,
    UpdateGroupChatRequest,
    GroupMemberAdminRequest,
    GroupMemberPermissionsRequest,
    GroupMemberSendRestrictionRequest,
    GroupMemberBanRequest,
    GroupMemberBanResponse,
    GroupMemberBanListResponse,
    GroupInviteLinkCreateRequest,
    GroupInviteLinkResponse,
    GroupInviteLinkListResponse,
    GroupJoinRequestListResponse,
    GroupJoinRequestResponse,
    GroupJoinRequestReviewRequest,
    JoinByInviteResponse,
    JoinRequestsInboxItemResponse,
    JoinRequestsInboxResponse,
    GroupModerationLogItemResponse,
    GroupModerationLogResponse,
    UpdateChatFolderRequest,
    MessageListResponse,
    MessageResponse,
    PhoneContactMatchItem,
    PinMessageRequest,
    PhoneSyncRequest,
    PhoneSyncResponse,
    SendMessageRequest,
    ChatPollAddOptionRequest,
    ChatPollVoteRequest,
    CallbackQueryRequest,
)
from app.models.bot_command import BotCommand
from app.models.conversation import (
    Conversation,
    ConversationMember,
    GroupInviteLink,
    GroupJoinRequest,
    Message,
    ScheduledMessage,
)
from app.services.chat_event_bus import publish as publish_chat_event
from app.services.chat_event_bus import subscribe as subscribe_chat_events
from app.services.chat_service import ChatService
from app.services.user_event_bus import publish_user_event
from app.services.analytics_service import AnalyticsService
from app.services.bot_webhook_queue_service import enqueue_webhook_task

router = APIRouter()


def _enforce_chat_action_rate_limit(user_id: int, action: str, limit: int) -> None:
    if not getattr(settings, "RATE_LIMIT_ENABLED", True):
        return
    from app.core.redis_client import REDIS_IS_STUB, get_redis

    if REDIS_IS_STUB:
        return
    key = f"rl:chat:{action}:{user_id}:minute"
    try:
        count = get_redis().incr(key)
        if count == 1:
            get_redis().expire(key, 60)
        if count > limit:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail={
                    "code": "CHAT_RATE_LIMIT_EXCEEDED",
                    "message": "Too many chat actions. Please try again later.",
                },
                headers={"Retry-After": "60"},
            )
    except HTTPException:
        raise
    except Exception:
        return


def _message_payload(msg, reactions: Optional[List[dict]] = None) -> Dict[str, Any]:
    inline_keyboard = None
    raw_keyboard = getattr(msg, "inline_keyboard_json", None)
    if raw_keyboard:
        try:
            parsed = json.loads(raw_keyboard)
            if isinstance(parsed, list):
                inline_keyboard = parsed
        except Exception:
            inline_keyboard = None
    return {
        "id": msg.id,
        "conversation_id": msg.conversation_id,
        "sender_id": msg.sender_id,
        "type": msg.type,
        "content": msg.content,
        "media_url": msg.media_url,
        "reply_to_message_id": msg.reply_to_message_id,
        "forward_from_user_id": getattr(msg, "forward_from_user_id", None),
        "forward_from_name": getattr(msg, "forward_from_name", None),
        "forwarded_from_message_id": getattr(msg, "forwarded_from_message_id", None),
        "inline_keyboard": inline_keyboard,
        "created_at": msg.created_at.isoformat() if msg.created_at else None,
        "edited_at": msg.edited_at.isoformat() if getattr(msg, "edited_at", None) else None,
        "reactions": reactions or [],
    }


def _scheduled_message_response(item: ScheduledMessage) -> ScheduledMessageResponse:
    return ScheduledMessageResponse(
        id=item.id,
        conversation_id=item.conversation_id,
        sender_id=item.sender_id,
        type=item.type,
        content=item.content,
        media_url=item.media_url,
        reply_to_message_id=item.reply_to_message_id,
        send_at=item.send_at,
        send_when_online=getattr(item, "deliver_when_online", False),
        status=item.status,
        created_at=item.created_at,
    )


def _enriched_content(
    db: Session, msg, viewer_user_id: int, cache: Optional[Dict[int, str]] = None
) -> str:
    if getattr(msg, "type", None) != "poll":
        return msg.content
    if cache is not None and msg.id in cache:
        return cache[msg.id]
    from app.services.chat_poll_service import enrich_poll_content

    return enrich_poll_content(db, msg.id, msg.content, viewer_user_id)


def _reaction_summaries(
    svc: ChatService, message_ids: List[int], user_id: int
) -> Dict[int, List[MessageReactionSummary]]:
    raw = svc.reactions_for_messages(message_ids, user_id)
    return {
        mid: [MessageReactionSummary(**item) for item in items]
        for mid, items in raw.items()
    }


def _emit(conversation_id: int, event: Dict[str, Any]) -> None:
    publish_chat_event(conversation_id, event)


def _notify_chat_inbox(
    db: Session, conversation_id: int, sender_id: int
) -> None:
    member_ids = (
        db.query(ConversationMember.user_id)
        .filter(ConversationMember.conversation_id == conversation_id)
        .all()
    )
    for (user_id,) in member_ids:
        if user_id == sender_id:
            continue
        publish_user_event(
            user_id,
            {
                "event": "chat.inbox",
                "conversation_id": conversation_id,
            },
        )


def _find_chat_bot(db: Session, conversation_id: int) -> Optional[User]:
    member_ids = (
        db.query(ConversationMember.user_id)
        .filter(ConversationMember.conversation_id == conversation_id)
        .all()
    )
    if not member_ids:
        return None
    user_ids = [uid for (uid,) in member_ids]
    if not user_ids:
        return None
    return (
        db.query(User)
        .filter(User.id.in_(user_ids), User.is_bot.is_(True))
        .first()
    )


def _enqueue_bot_webhook(
    db: Session,
    *,
    conversation_id: int,
    update_type: str,
    payload: Dict[str, Any],
) -> bool:
    bot = _find_chat_bot(db, conversation_id)
    if not bot:
        return False
    enqueue_webhook_task(
        bot_id=bot.id,
        update_type=update_type,
        payload=payload,
    )
    return True


def _brief(
    user: User,
    *,
    is_group_admin: bool = False,
    is_group_creator: bool = False,
    can_manage_members: bool = False,
    can_manage_posting_permissions: bool = False,
    send_restricted: bool = False,
    send_restricted_until: Optional[datetime] = None,
    send_restriction_reason: Optional[str] = None,
) -> ChatUserBrief:
    return ChatUserBrief(
        id=user.id,
        name=user.name,
        username=user.username,
        avatar_url=user.avatar_url,
        last_seen_at=user.last_seen_at,
        is_bot=bool(getattr(user, "is_bot", False)),
        is_group_admin=is_group_admin,
        is_group_creator=is_group_creator,
        can_manage_members=can_manage_members,
        can_manage_posting_permissions=can_manage_posting_permissions,
        send_restricted=send_restricted,
        send_restricted_until=send_restricted_until,
        send_restriction_reason=send_restriction_reason,
    )


def _group_ban_response(item: dict) -> GroupMemberBanResponse:
    return GroupMemberBanResponse(
        user=_brief(item["user"]),
        reason=item.get("reason"),
        banned_until=item.get("banned_until"),
        banned_at=item.get("banned_at"),
    )


def _group_join_request_response(item: dict) -> GroupJoinRequestResponse:
    return GroupJoinRequestResponse(
        id=item["id"],
        user=_brief(item["user"]),
        status=item["status"],
        requested_at=item["requested_at"],
    )


def _invite_link_from_token(token: str) -> str:
    # Public web link also works for deep-link parsing in app.
    return f"https://haneat.app/chat-invite/{token}"


def _invite_link_response(row: GroupInviteLink) -> GroupInviteLinkResponse:
    return GroupInviteLinkResponse(
        id=row.id,
        token=row.token,
        invite_link=_invite_link_from_token(row.token),
        expires_at=row.expires_at,
        max_uses=row.max_uses,
        uses_count=row.uses_count,
        revoked_at=row.revoked_at,
        created_at=row.created_at,
    )


def _moderation_action_from_text(text: str) -> str:
    t = (text or "").lower()
    if "join request" in t:
        return "joins"
    if "banned" in t or "unbanned" in t:
        return "bans"
    if "restricted messaging" in t or "messaging restriction" in t:
        return "restrictions"
    if "moderator role" in t or "moderator permissions" in t:
        return "roles"
    if (
        "changed group title" in t
        or "sending mode changed" in t
        or "join mode changed" in t
    ):
        return "settings"
    return "other"


def _peer_last_read_id(
    db: Session, svc: ChatService, conv, current_user_id: int
) -> Optional[int]:
    if conv.type != "direct":
        return None
    peer_id = svc.peer_user_id(conv, current_user_id)
    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conv.id,
            ConversationMember.user_id == peer_id,
        )
        .first()
    )
    return member.last_read_message_id if member else None


def _peer_last_delivered_id(
    db: Session, svc: ChatService, conv, current_user_id: int
) -> Optional[int]:
    if conv.type != "direct":
        return None
    peer_id = svc.peer_user_id(conv, current_user_id)
    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conv.id,
            ConversationMember.user_id == peer_id,
        )
        .first()
    )
    if not member:
        return None
    delivered = getattr(member, "last_delivered_message_id", None)
    read = member.last_read_message_id
    if delivered is None:
        return read
    if read is None:
        return delivered
    return max(delivered, read)


def _sender_name(user: Optional[User]) -> Optional[str]:
    if not user:
        return None
    return user.name or user.username


def _user_label(user: Optional[User], fallback_id: Optional[int] = None) -> str:
    if user is not None:
        if user.name and user.name.strip():
            return user.name.strip()
        if user.username and user.username.strip():
            return f"@{user.username.strip()}"
        return f"User {user.id}"
    if fallback_id is not None:
        return f"User {fallback_id}"
    return "User"


def _normalize_inline_keyboard(raw: Any) -> Optional[List[List[Dict[str, Any]]]]:
    if raw in (None, ""):
        return None
    source = raw
    if isinstance(raw, str):
        try:
            source = json.loads(raw)
        except Exception:
            return None
    if not isinstance(source, list):
        return None
    rows: List[List[Dict[str, Any]]] = []
    for row in source:
        if not isinstance(row, list):
            continue
        out_row: List[Dict[str, Any]] = []
        for btn in row:
            if hasattr(btn, "model_dump"):
                btn = btn.model_dump(exclude_none=True)
            if not isinstance(btn, dict):
                continue
            text = str(btn.get("text") or "").strip()[:64]
            if not text:
                continue
            callback_data = btn.get("callback_data")
            url = btn.get("url")
            callback_text = btn.get("callback_text")
            out_btn: Dict[str, Any] = {"text": text}
            if isinstance(callback_data, str) and callback_data.strip():
                out_btn["callback_data"] = callback_data.strip()[:128]
            if isinstance(url, str) and url.strip():
                out_btn["url"] = url.strip()[:512]
            if isinstance(callback_text, str) and callback_text.strip():
                out_btn["callback_text"] = callback_text.strip()[:300]
            if "callback_data" not in out_btn and "url" not in out_btn:
                continue
            out_row.append(out_btn)
        if out_row:
            rows.append(out_row)
    return rows or None


def _message_response(
    msg,
    current_user_id: int,
    my_last_read_id: Optional[int],
    peer_last_read_id: Optional[int] = None,
    conv: Optional[Conversation] = None,
    svc: Optional[ChatService] = None,
    sender: Optional[User] = None,
    reactions: Optional[List[MessageReactionSummary]] = None,
    db: Optional[Session] = None,
    poll_content_cache: Optional[Dict[int, str]] = None,
    peer_last_delivered_id: Optional[int] = None,
) -> MessageResponse:
    is_mine = msg.sender_id == current_user_id
    if is_mine and conv and conv.type == "group" and svc:
        is_read = svc.group_all_read(conv.id, msg.id, current_user_id)
    elif is_mine and conv and conv.type == "saved":
        is_read = True
    elif is_mine:
        is_read = bool(
            peer_last_read_id is not None and msg.id <= peer_last_read_id
        )
    elif my_last_read_id and msg.id <= my_last_read_id:
        is_read = True
    else:
        is_read = False

    if (
        peer_last_delivered_id is None
        and is_mine
        and conv is not None
        and conv.type == "direct"
        and svc is not None
        and db is not None
    ):
        peer_last_delivered_id = _peer_last_delivered_id(
            db, svc, conv, current_user_id
        )

    if is_read:
        is_delivered = True
    elif is_mine and conv and conv.type == "saved":
        is_delivered = True
    elif is_mine and conv and conv.type == "group" and svc:
        is_delivered = svc.group_all_delivered(conv.id, msg.id, current_user_id)
    elif is_mine:
        is_delivered = bool(
            peer_last_delivered_id is not None
            and msg.id <= peer_last_delivered_id
        )
    else:
        is_delivered = False

    content = msg.content
    if db is not None and getattr(msg, "type", None) == "poll":
        content = _enriched_content(db, msg, current_user_id, poll_content_cache)
    inline_keyboard = _normalize_inline_keyboard(getattr(msg, "inline_keyboard_json", None))
    return MessageResponse(
        id=msg.id,
        conversation_id=msg.conversation_id,
        sender_id=msg.sender_id,
        sender_name=_sender_name(sender),
        type=msg.type,
        content=content,
        media_url=msg.media_url,
        reply_to_message_id=msg.reply_to_message_id,
        forward_from_user_id=getattr(msg, "forward_from_user_id", None),
        forward_from_name=getattr(msg, "forward_from_name", None),
        forwarded_from_message_id=getattr(msg, "forwarded_from_message_id", None),
        inline_keyboard=inline_keyboard,
        created_at=msg.created_at,
        edited_at=getattr(msg, "edited_at", None),
        is_mine=is_mine,
        is_delivered=is_delivered,
        is_read=is_read,
        reactions=reactions or [],
    )


def _conversation_response(
    row: dict,
    svc: ChatService,
    db: Session,
    current_user: User,
) -> Optional[ConversationResponse]:
    conv = row["conversation"]
    peer = row.get("peer")
    if conv.type == "direct" and not peer:
        return None
    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conv.id,
            ConversationMember.user_id == current_user.id,
        )
        .first()
    )
    am_i_group_admin = bool(
        conv.type == "group"
        and (
            conv.created_by_user_id == current_user.id
            or (member is not None and member.is_admin)
        )
    )
    am_i_can_manage_members = bool(
        conv.type == "group"
        and (
            conv.created_by_user_id == current_user.id
            or (
                member is not None
                and member.is_admin
                and member.can_manage_members
            )
        )
    )
    am_i_can_manage_posting_permissions = bool(
        conv.type == "group"
        and (
            conv.created_by_user_id == current_user.id
            or (
                member is not None
                and member.is_admin
                and member.can_manage_posting_permissions
            )
        )
    )
    am_i_send_restricted = False
    am_i_send_restricted_until = None
    am_i_send_restriction_reason = None
    if conv.type == "group" and member is not None:
        restricted, restricted_until, restricted_reason = (
            svc.member_send_restriction_state(conv.id, current_user.id)
        )
        am_i_send_restricted = restricted
        am_i_send_restricted_until = restricted_until
        am_i_send_restriction_reason = restricted_reason
    pending_join_requests_count = 0
    if conv.type == "group" and am_i_can_manage_members:
        pending_join_requests_count = (
            db.query(func.count(GroupJoinRequest.id))
            .filter(
                GroupJoinRequest.conversation_id == conv.id,
                GroupJoinRequest.status == "pending",
            )
            .scalar()
            or 0
        )
    peer_read = _peer_last_read_id(db, svc, conv, current_user.id)
    peer_delivered = _peer_last_delivered_id(db, svc, conv, current_user.id)
    peer_blocked_by_me = False
    if conv.type == "direct" and peer is not None:
        peer_blocked_by_me = svc.is_user_blocked_by_me(current_user.id, peer.id)
    last = row.get("last_message")
    last_resp = None
    if last:
        sender = (
            db.query(User).filter(User.id == last.sender_id).first()
            if conv.type == "group"
            else None
        )
        last_resp = _message_response(
            last,
            current_user.id,
            member.last_read_message_id if member else None,
            peer_read,
            conv,
            svc,
            sender,
            peer_last_delivered_id=peer_delivered,
        )
    return ConversationResponse(
        id=conv.id,
        type=conv.type,
        peer=_brief(peer) if peer else None,
        title=conv.title if conv.type in ("group", "saved") else None,
        member_count=row.get("member_count", 0),
        pending_join_requests_count=pending_join_requests_count,
        members_preview=[
            _brief(u) for u in row.get("members_preview", []) if u
        ],
        last_message=last_resp,
        unread_count=row.get("unread_count", 0),
        updated_at=conv.updated_at or conv.created_at,
        pinned=row.get("pinned", False),
        archived=row.get("archived", False),
        muted=row.get("muted", False),
        created_by_user_id=conv.created_by_user_id
        if conv.type in ("group", "saved")
        else None,
        only_admins_can_post=bool(getattr(conv, "only_admins_can_post", False)),
        join_by_request_enabled=bool(getattr(conv, "join_by_request_enabled", False)),
        slow_mode_seconds=int(getattr(conv, "slow_mode_seconds", 0) or 0),
        anti_flood_max_messages_per_minute=int(
            getattr(conv, "anti_flood_max_messages_per_minute", 0) or 0
        ),
        protect_content=bool(getattr(conv, "protect_content", False)),
        am_i_group_admin=am_i_group_admin,
        am_i_can_manage_members=am_i_can_manage_members,
        am_i_can_manage_posting_permissions=am_i_can_manage_posting_permissions,
        am_i_send_restricted=am_i_send_restricted,
        am_i_send_restricted_until=am_i_send_restricted_until,
        am_i_send_restriction_reason=am_i_send_restriction_reason,
        peer_blocked_by_me=peer_blocked_by_me,
    )


def _search_response_items(
    db: Session,
    svc: ChatService,
    current_user: User,
    hits: List[dict],
) -> MessageSearchResponse:
    items: List[MessageSearchItem] = []
    for hit in hits:
        msg = hit["message"]
        row = hit.get("conversation_row")
        if not row:
            continue
        conv_item = _conversation_response(row, svc, db, current_user)
        if not conv_item:
            continue
        conv = row["conversation"]
        member = (
            db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conv.id,
                ConversationMember.user_id == current_user.id,
            )
            .first()
        )
        peer_read = _peer_last_read_id(db, svc, conv, current_user.id)
        peer_delivered = _peer_last_delivered_id(db, svc, conv, current_user.id)
        msg_resp = _message_response(
            msg,
            current_user.id,
            member.last_read_message_id if member else None,
            peer_read,
            conv,
            svc,
            hit.get("sender"),
            db=db,
            peer_last_delivered_id=peer_delivered,
        )
        items.append(
            MessageSearchItem(
                message=msg_resp,
                conversation=conv_item,
                snippet=hit.get("snippet") or "",
            )
        )
    return MessageSearchResponse(items=items)


@router.get("/chats", response_model=ConversationListResponse)
async def list_chats(
    archived: bool = Query(False),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    _enforce_chat_action_rate_limit(current_user.id, "send", 45)
    svc = ChatService(db)
    rows = svc.list_conversations(current_user.id, archived_only=archived)
    db.commit()
    items = []
    total_unread = 0
    for row in rows:
        item = _conversation_response(row, svc, db, current_user)
        if not item:
            continue
        total_unread += item.unread_count
        items.append(item)
    return ConversationListResponse(items=items, total_unread=total_unread)


@router.get("/chats/unread-count")
async def chats_unread_count(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    return {"count": ChatService(db).total_unread(current_user.id)}


@router.get("/chats/saved", response_model=ConversationResponse)
async def get_saved_chat(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    _enforce_chat_action_rate_limit(current_user.id, "typing", 120)
    svc = ChatService(db)
    conv = svc.get_or_create_saved(current_user.id)
    db.commit()
    row = svc.get_conversation_row(conv.id, current_user.id)
    if not row:
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "Saved chat failed")
    item = _conversation_response(row, svc, db, current_user)
    if not item:
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "Saved chat failed")
    return item


@router.get("/chats/folders", response_model=ChatFolderListResponse)
async def list_chat_folders(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    items = [ChatFolderResponse(**row) for row in svc.list_folders(current_user.id)]
    return ChatFolderListResponse(items=items)


@router.post("/chats/folders", response_model=ChatFolderResponse)
async def create_chat_folder(
    body: CreateChatFolderRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        row = svc.create_folder(
            current_user.id,
            body.name,
            body.icon,
            body.conversation_ids,
            body.channel_ids,
            body.filters,
        )
        db.commit()
        return ChatFolderResponse(**row)
    except ValueError as e:
        db.rollback()
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(e)) from e


@router.post("/chats/folders/reorder", response_model=ChatFolderListResponse)
async def reorder_chat_folders(
    body: ReorderChatFoldersRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    rows = svc.reorder_folders(current_user.id, body.folder_ids)
    db.commit()
    return ChatFolderListResponse(items=[ChatFolderResponse(**row) for row in rows])


@router.patch("/chats/folders/{folder_id}", response_model=ChatFolderResponse)
async def update_chat_folder(
    folder_id: int,
    body: UpdateChatFolderRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        row = svc.update_folder(
            current_user.id,
            folder_id,
            body.name,
            body.icon,
            body.conversation_ids,
            body.channel_ids,
            body.filters,
        )
    except ValueError as e:
        db.rollback()
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(e)) from e
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Folder not found")
    db.commit()
    return ChatFolderResponse(**row)


@router.delete("/chats/folders/{folder_id}")
async def delete_chat_folder(
    folder_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    ok = svc.delete_folder(current_user.id, folder_id)
    db.commit()
    if not ok:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Folder not found")
    return {"ok": True}


@router.post("/chats/folders/{folder_id}/items", response_model=ChatFolderResponse)
async def add_chat_folder_item(
    folder_id: int,
    body: ChatFolderItemRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        row = svc.add_folder_item(
            current_user.id,
            folder_id,
            body.conversation_id,
            body.channel_id,
        )
    except ValueError as e:
        db.rollback()
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(e)) from e
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Folder not found")
    db.commit()
    return ChatFolderResponse(**row)


@router.delete("/chats/folders/{folder_id}/items", response_model=ChatFolderResponse)
async def remove_chat_folder_item(
    folder_id: int,
    conversation_id: Optional[int] = Query(None),
    channel_id: Optional[int] = Query(None),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        row = svc.remove_folder_item(
            current_user.id,
            folder_id,
            conversation_id,
            channel_id,
        )
    except ValueError as e:
        db.rollback()
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(e)) from e
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Folder not found")
    db.commit()
    return ChatFolderResponse(**row)


@router.get("/chats/{conversation_id}", response_model=ConversationResponse)
async def get_chat(
    conversation_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    row = svc.get_conversation_row(conversation_id, current_user.id)
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Conversation not found")
    item = _conversation_response(row, svc, db, current_user)
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Conversation not found")
    return item


@router.post("/chats/direct", response_model=ConversationResponse)
async def open_direct_chat(
    body: DirectChatRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        conv = svc.get_or_create_direct(current_user.id, body.user_id)
        db.commit()
        db.refresh(conv)
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "user_not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
        if code == "self_chat":
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "Cannot chat with yourself")
        if code == "user_blocked":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "User blocked")
        raise

    peer_id = svc.peer_user_id(conv, current_user.id)
    peer = db.query(User).filter(User.id == peer_id).first()
    if not peer:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
    row = svc.get_conversation_row(conv.id, current_user.id)
    item = _conversation_response(row, svc, db, current_user) if row else None
    if not item:
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "Chat create failed")
    return item


@router.post("/chats/group", response_model=ConversationResponse)
async def create_group_chat(
    body: CreateGroupChatRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        conv = svc.create_group(current_user.id, body.title, body.member_ids)
        db.commit()
        db.refresh(conv)
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "user_not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
        if code in ("empty_title", "need_members"):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        if code == "user_blocked":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "User blocked")
        raise
    row = svc.get_conversation_row(conv.id, current_user.id)
    item = _conversation_response(row, svc, db, current_user) if row else None
    if not item:
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "Group create failed")
    return item


@router.get(
    "/chats/{conversation_id}/invite-link",
    response_model=GroupInviteLinkResponse,
)
async def get_group_invite_link(
    conversation_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        token = svc.get_or_create_group_invite_token(
            conversation_id,
            current_user.id,
            rotate=False,
        )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code in ("forbidden", "not_group"):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        raise
    row = db.query(GroupInviteLink).filter(GroupInviteLink.token == token).first()
    if not row:
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "Invite link error")
    return _invite_link_response(row)


@router.post(
    "/chats/{conversation_id}/invite-link/rotate",
    response_model=GroupInviteLinkResponse,
)
async def rotate_group_invite_link(
    conversation_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        token = svc.get_or_create_group_invite_token(
            conversation_id,
            current_user.id,
            rotate=True,
        )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code in ("forbidden", "not_group"):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        raise
    row = db.query(GroupInviteLink).filter(GroupInviteLink.token == token).first()
    if not row:
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "Invite link error")
    return _invite_link_response(row)


@router.get(
    "/chats/{conversation_id}/invite-links",
    response_model=GroupInviteLinkListResponse,
)
async def list_group_invite_links(
    conversation_id: int,
    include_revoked: bool = Query(True),
    limit: int = Query(200, ge=1, le=500),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        rows = svc.list_group_invite_links(
            conversation_id,
            current_user.id,
            include_revoked=include_revoked,
            limit=limit,
        )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code in ("forbidden", "not_group"):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        raise
    return GroupInviteLinkListResponse(items=[_invite_link_response(r) for r in rows])


@router.post(
    "/chats/{conversation_id}/invite-links",
    response_model=GroupInviteLinkResponse,
)
async def create_group_invite_link(
    conversation_id: int,
    body: GroupInviteLinkCreateRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        row = svc.create_group_invite_link(
            conversation_id,
            current_user.id,
            expires_at=body.expires_at,
            max_uses=body.max_uses,
        )
        db.commit()
        db.refresh(row)
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code in ("forbidden", "not_group"):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        if code in ("invalid_invite_expiry", "invalid_invite_max_uses"):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        raise
    return _invite_link_response(row)


@router.delete("/chats/{conversation_id}/invite-links/{invite_link_id}")
async def revoke_group_invite_link(
    conversation_id: int,
    invite_link_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        svc.revoke_group_invite_link(
            conversation_id,
            current_user.id,
            invite_link_id,
        )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Invite link not found")
        if code in ("forbidden", "not_group"):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        raise
    return {"ok": True}


@router.post("/chats/join/{invite_token}", response_model=JoinByInviteResponse)
async def join_group_by_invite(
    invite_token: str,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        result = svc.join_group_by_invite_token(invite_token, current_user.id)
        db.commit()
        conv = result["conversation"]
        db.refresh(conv)
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code in ("invalid_invite",):
            raise HTTPException(status.HTTP_404_NOT_FOUND, code)
        if code == "group_member_banned":
            raise HTTPException(status.HTTP_403_FORBIDDEN, code)
        if code == "user_not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
        raise
    if result["status"] == "requested":
        for manager_id in svc.group_member_manager_user_ids(conv.id):
            if manager_id == current_user.id:
                continue
            publish_user_event(
                manager_id,
                {
                    "event": "chat.join_request.new",
                    "notification_type": "chat_join_request",
                    "conversation_id": conv.id,
                },
            )
        return JoinByInviteResponse(status="requested", conversation=None)
    row = svc.get_conversation_row(conv.id, current_user.id)
    item = _conversation_response(row, svc, db, current_user) if row else None
    if not item:
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "Join failed")
    return JoinByInviteResponse(status="joined", conversation=item)


@router.get(
    "/chats/{conversation_id}/members",
    response_model=ConversationMembersResponse,
)
async def list_chat_members(
    conversation_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        members = svc.list_members(conversation_id, current_user.id)
    except ValueError:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    return ConversationMembersResponse(
        items=[
            _brief(
                m["user"],
                is_group_admin=m.get("is_group_admin", False),
                is_group_creator=m.get("is_group_creator", False),
                can_manage_members=m.get("can_manage_members", False),
                can_manage_posting_permissions=m.get(
                    "can_manage_posting_permissions", False
                ),
                send_restricted=m.get("send_restricted", False),
                send_restricted_until=m.get("send_restricted_until"),
                send_restriction_reason=m.get("send_restriction_reason"),
            )
            for m in members
        ]
    )


@router.get("/chats/{conversation_id}/messages", response_model=MessageListResponse)
async def list_messages(
    conversation_id: int,
    cursor: Optional[int] = Query(None),
    after_id: Optional[int] = Query(None),
    limit: int = Query(50, ge=1, le=100),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        messages, has_more = svc.get_messages(
            conversation_id,
            current_user.id,
            cursor,
            after_id,
            limit,
        )
    except ValueError:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")

    dispatched = svc.dispatch_scheduled_messages(conversation_id)
    if dispatched:
        db.commit()
        for msg in dispatched:
            _emit(
                conversation_id,
                {"type": "message.new", "message": _message_payload(msg)},
            )
            _notify_chat_inbox(db, conversation_id, msg.sender_id)
        db.commit()
        messages, has_more = svc.get_messages(
            conversation_id,
            current_user.id,
            cursor,
            after_id,
            limit,
        )

    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == current_user.id,
        )
        .first()
    )
    last_read = member.last_read_message_id if member else None
    conv = (
        db.query(Conversation)
        .filter(Conversation.id == conversation_id)
        .first()
    )
    peer_read = _peer_last_read_id(db, svc, conv, current_user.id) if conv else None
    peer_delivered = (
        _peer_last_delivered_id(db, svc, conv, current_user.id) if conv else None
    )
    sender_ids = {m.sender_id for m in messages}
    senders = {
        u.id: u
        for u in db.query(User).filter(User.id.in_(sender_ids)).all()
    } if sender_ids else {}
    message_ids = [m.id for m in messages]
    reactions_map = _reaction_summaries(svc, message_ids, current_user.id)
    from app.services.chat_poll_service import enrich_messages_poll_batch

    poll_cache = enrich_messages_poll_batch(db, messages, current_user.id)

    items = [
        _message_response(
            m,
            current_user.id,
            last_read,
            peer_read,
            conv,
            svc,
            senders.get(m.sender_id),
            reactions=reactions_map.get(m.id, []),
            db=db,
            poll_content_cache=poll_cache,
            peer_last_delivered_id=peer_delivered,
        )
        for m in messages
    ]
    pinned_resp = None
    pinned_msg = svc.get_pinned_message(conversation_id, current_user.id)
    if pinned_msg:
        pinned_reactions = _reaction_summaries(
            svc, [pinned_msg.id], current_user.id
        ).get(pinned_msg.id, [])
        pinned_sender = senders.get(pinned_msg.sender_id)
        if pinned_sender is None:
            pinned_sender = (
                db.query(User).filter(User.id == pinned_msg.sender_id).first()
            )
        pinned_resp = _message_response(
            pinned_msg,
            current_user.id,
            last_read,
            peer_read,
            conv,
            svc,
            pinned_sender,
            reactions=pinned_reactions,
            db=db,
            poll_content_cache=poll_cache,
            peer_last_delivered_id=peer_delivered,
        )
    next_cursor = None
    if after_id is None:
        next_cursor = messages[0].id if has_more and messages else None
    return MessageListResponse(
        items=items,
        has_more=has_more,
        next_cursor=next_cursor,
        pinned_message=pinned_resp if after_id is None else None,
    )


@router.get(
    "/chats/{conversation_id}/media",
    response_model=MessageListResponse,
)
async def list_chat_media(
    conversation_id: int,
    kind: str = Query(
        "all",
        pattern="^(all|photos|videos|files|links|voices|stickers)$",
    ),
    cursor: Optional[int] = Query(None),
    limit: int = Query(60, ge=1, le=100),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Shared media / links / voice across full chat history."""
    svc = ChatService(db)
    try:
        messages, has_more = svc.list_media_messages(
            conversation_id,
            current_user.id,
            kind=kind,
            cursor=cursor,
            limit=limit,
        )
    except ValueError:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")

    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == current_user.id,
        )
        .first()
    )
    last_read = member.last_read_message_id if member else None
    conv = (
        db.query(Conversation)
        .filter(Conversation.id == conversation_id)
        .first()
    )
    peer_read = _peer_last_read_id(db, svc, conv, current_user.id) if conv else None
    peer_delivered = (
        _peer_last_delivered_id(db, svc, conv, current_user.id) if conv else None
    )
    sender_ids = {m.sender_id for m in messages}
    senders = {
        u.id: u
        for u in db.query(User).filter(User.id.in_(sender_ids)).all()
    } if sender_ids else {}
    message_ids = [m.id for m in messages]
    reactions_map = _reaction_summaries(svc, message_ids, current_user.id)
    from app.services.chat_poll_service import enrich_messages_poll_batch

    poll_cache = enrich_messages_poll_batch(db, messages, current_user.id)
    items = [
        _message_response(
            m,
            current_user.id,
            last_read,
            peer_read,
            conv,
            svc,
            senders.get(m.sender_id),
            reactions=reactions_map.get(m.id, []),
            db=db,
            poll_content_cache=poll_cache,
            peer_last_delivered_id=peer_delivered,
        )
        for m in messages
    ]
    next_cursor = messages[-1].id if has_more and messages else None
    return MessageListResponse(
        items=items,
        has_more=has_more,
        next_cursor=next_cursor,
        pinned_message=None,
    )


@router.get("/chats/messages/search", response_model=MessageSearchResponse)
async def search_messages_global(
    q: str = Query(..., min_length=2),
    type: Optional[str] = Query(
        None,
        pattern="^(text|image|voice|file|video|video_note|poll|sticker|location)$",
    ),
    limit: int = Query(40, ge=1, le=100),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        hits = svc.search_messages(
            current_user.id,
            q,
            msg_type=type,
            limit=limit,
        )
    except ValueError:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    return _search_response_items(db, svc, current_user, hits)


@router.get(
    "/chats/{conversation_id}/messages/search",
    response_model=MessageSearchResponse,
)
async def search_messages_in_chat(
    conversation_id: int,
    q: str = Query(..., min_length=2),
    type: Optional[str] = Query(
        None,
        pattern="^(text|image|voice|file|video|video_note|poll|sticker|location)$",
    ),
    limit: int = Query(40, ge=1, le=100),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        hits = svc.search_messages(
            current_user.id,
            q,
            conversation_id=conversation_id,
            msg_type=type,
            limit=limit,
        )
    except ValueError:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    return _search_response_items(db, svc, current_user, hits)


@router.post("/chats/{conversation_id}/messages", response_model=MessageResponse)
async def send_message(
    conversation_id: int,
    body: SendMessageRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    content = body.content
    inline_keyboard_payload = _normalize_inline_keyboard(body.inline_keyboard)
    webhook_touched = False
    if body.type == "poll":
        from app.services.chat_poll_service import build_poll_content

        if not body.poll_question or not body.poll_options:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST, "poll_fields_required"
            )
        try:
            content = build_poll_content(
                body.poll_question,
                body.poll_options,
                description=body.poll_description or "",
                settings=body.poll_settings,
            )
        except ValueError as e:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, str(e))
    try:
        msg, is_new = svc.send_message(
            conversation_id=conversation_id,
            sender_id=current_user.id,
            msg_type=body.type,
            content=content,
            media_url=body.media_url,
            reply_to_message_id=body.reply_to_message_id,
            client_message_id=body.client_message_id,
            inline_keyboard_json=json.dumps(inline_keyboard_payload, ensure_ascii=False)
            if inline_keyboard_payload
            else None,
            silent=bool(body.silent),
        )
        db.commit()
        db.refresh(msg)

        # === Встроенный обработчик ботов ===
        from app.services.bot_handler import process_message_for_bot
        bot_reply = process_message_for_bot(db, conversation_id, current_user.id, content)
        if bot_reply:
            db.commit()
            db.refresh(bot_reply)
            _emit(
                conversation_id,
                {"type": "message.new", "message": _message_payload(bot_reply)},
            )
            webhook_touched = _enqueue_bot_webhook(
                db,
                conversation_id=conversation_id,
                update_type="message.bot_reply",
                payload={
                    "conversation_id": conversation_id,
                    "from_user_id": current_user.id,
                    "message": _message_payload(bot_reply),
                },
            ) or webhook_touched
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        if code in (
            "empty_message",
            "missing_media",
            "empty_poll",
            "empty_location",
            "invalid_reply",
        ):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        if code == "user_blocked":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "User blocked")
        if code == "group_write_restricted":
            raise HTTPException(status.HTTP_403_FORBIDDEN, code)
        if code == "group_user_restricted":
            raise HTTPException(status.HTTP_403_FORBIDDEN, code)
        if code == "group_slow_mode":
            raise HTTPException(
                status.HTTP_429_TOO_MANY_REQUESTS,
                {
                    "code": code,
                    "retry_after_seconds": svc.group_slow_mode_retry_after_seconds(
                        conversation_id,
                        current_user.id,
                    ),
                },
            )
        if code == "group_flood_limited":
            raise HTTPException(
                status.HTTP_429_TOO_MANY_REQUESTS,
                {
                    "code": code,
                    "retry_after_seconds": svc.group_flood_retry_after_seconds(
                        conversation_id,
                        current_user.id,
                    ),
                },
            )
        raise

    if is_new:
        _emit(
            conversation_id,
            {"type": "message.new", "message": _message_payload(msg)},
        )
        _notify_chat_inbox(db, conversation_id, current_user.id)
        webhook_touched = _enqueue_bot_webhook(
            db,
            conversation_id=conversation_id,
            update_type="message.new",
            payload={
                "conversation_id": conversation_id,
                "from_user_id": current_user.id,
                "message": _message_payload(msg),
            },
        ) or webhook_touched
    if webhook_touched:
        db.commit()
    conv = (
        db.query(Conversation)
        .filter(Conversation.id == conversation_id)
        .first()
    )
    peer_read = _peer_last_read_id(db, svc, conv, current_user.id) if conv else None
    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == current_user.id,
        )
        .first()
    )
    sender = db.query(User).filter(User.id == msg.sender_id).first()
    return _message_response(
        msg,
        current_user.id,
        member.last_read_message_id if member else None,
        peer_read,
        conv,
        svc,
        sender,
        db=db,
    )


@router.post(
    "/chats/{conversation_id}/messages/forward",
    response_model=MessageResponse,
)
async def forward_message(
    conversation_id: int,
    body: ForwardMessageRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        msg = svc.forward_message(
            target_conversation_id=conversation_id,
            source_conversation_id=body.source_conversation_id,
            message_id=body.message_id,
            sender_id=current_user.id,
            as_copy=bool(body.as_copy),
        )
        db.commit()
        db.refresh(msg)
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Message not found")
        if code in (
            "empty_message",
            "missing_media",
            "empty_poll",
            "empty_location",
            "invalid_reply",
        ):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        if code == "user_blocked":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "User blocked")
        if code == "protect_content":
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                "Content is protected",
            )
        if code in (
            "group_write_restricted",
            "group_user_restricted",
        ):
            raise HTTPException(status.HTTP_403_FORBIDDEN, code)
        if code == "group_slow_mode":
            raise HTTPException(
                status.HTTP_429_TOO_MANY_REQUESTS,
                {
                    "code": code,
                    "retry_after_seconds": svc.group_slow_mode_retry_after_seconds(
                        conversation_id,
                        current_user.id,
                    ),
                },
            )
        if code == "group_flood_limited":
            raise HTTPException(
                status.HTTP_429_TOO_MANY_REQUESTS,
                {
                    "code": code,
                    "retry_after_seconds": svc.group_flood_retry_after_seconds(
                        conversation_id,
                        current_user.id,
                    ),
                },
            )
        raise

    _emit(
        conversation_id,
        {"type": "message.new", "message": _message_payload(msg)},
    )
    _notify_chat_inbox(db, conversation_id, current_user.id)

    conv = (
        db.query(Conversation)
        .filter(Conversation.id == conversation_id)
        .first()
    )
    peer_read = _peer_last_read_id(db, svc, conv, current_user.id) if conv else None
    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == current_user.id,
        )
        .first()
    )
    sender = db.query(User).filter(User.id == msg.sender_id).first()
    return _message_response(
        msg,
        current_user.id,
        member.last_read_message_id if member else None,
        peer_read,
        conv,
        svc,
        sender,
        db=db,
    )


@router.post(
    "/chats/{conversation_id}/messages/scheduled",
    response_model=ScheduledMessageResponse,
)
async def schedule_message(
    conversation_id: int,
    body: ScheduleMessageRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    content = body.content
    inline_keyboard_payload = _normalize_inline_keyboard(body.inline_keyboard)
    if body.type == "poll":
        from app.services.chat_poll_service import build_poll_content

        if not body.poll_question or not body.poll_options:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST, "poll_fields_required"
            )
        try:
            content = build_poll_content(
                body.poll_question,
                body.poll_options,
                description=body.poll_description or "",
                settings=body.poll_settings,
            )
        except ValueError as e:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, str(e))
    try:
        item = svc.schedule_message(
            conversation_id=conversation_id,
            sender_id=current_user.id,
            msg_type=body.type,
            content=content,
            send_when_online=body.send_when_online,
            media_url=body.media_url,
            reply_to_message_id=body.reply_to_message_id,
            client_message_id=body.client_message_id,
            inline_keyboard_json=json.dumps(inline_keyboard_payload, ensure_ascii=False)
            if inline_keyboard_payload
            else None,
            send_at=body.send_at,
        )
        db.commit()
        db.refresh(item)
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        if code in (
            "empty_message",
            "missing_media",
            "empty_poll",
            "invalid_reply",
            "invalid_send_at",
            "when_online_direct_only",
        ):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        if code == "user_blocked":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "User blocked")
        if code == "group_write_restricted":
            raise HTTPException(status.HTTP_403_FORBIDDEN, code)
        if code == "group_user_restricted":
            raise HTTPException(status.HTTP_403_FORBIDDEN, code)
        if code == "group_slow_mode":
            raise HTTPException(
                status.HTTP_429_TOO_MANY_REQUESTS,
                {
                    "code": code,
                    "retry_after_seconds": svc.group_slow_mode_retry_after_seconds(
                        conversation_id,
                        current_user.id,
                    ),
                },
            )
        if code == "group_flood_limited":
            raise HTTPException(
                status.HTTP_429_TOO_MANY_REQUESTS,
                {
                    "code": code,
                    "retry_after_seconds": svc.group_flood_retry_after_seconds(
                        conversation_id,
                        current_user.id,
                    ),
                },
            )
        raise
    return _scheduled_message_response(item)


@router.get(
    "/chats/{conversation_id}/messages/scheduled",
    response_model=ScheduledMessageListResponse,
)
async def list_scheduled_messages(
    conversation_id: int,
    limit: int = Query(100, ge=1, le=200),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        items = svc.list_scheduled_messages(conversation_id, current_user.id, limit=limit)
    except ValueError:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    return ScheduledMessageListResponse(
        items=[_scheduled_message_response(i) for i in items]
    )


@router.delete(
    "/chats/{conversation_id}/messages/scheduled/{scheduled_message_id}",
    response_model=ScheduledMessageResponse,
)
async def cancel_scheduled_message(
    conversation_id: int,
    scheduled_message_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        item = svc.cancel_scheduled_message(
            conversation_id=conversation_id,
            scheduled_message_id=scheduled_message_id,
            user_id=current_user.id,
        )
        db.commit()
        db.refresh(item)
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Scheduled message not found")
        if code == "already_processed":
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    return _scheduled_message_response(item)


@router.patch(
    "/chats/{conversation_id}/messages/scheduled/{scheduled_message_id}",
    response_model=ScheduledMessageResponse,
)
async def reschedule_scheduled_message(
    conversation_id: int,
    scheduled_message_id: int,
    body: RescheduleMessageRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        item = svc.reschedule_message(
            conversation_id=conversation_id,
            scheduled_message_id=scheduled_message_id,
            user_id=current_user.id,
            send_at=body.send_at,
        )
        db.commit()
        db.refresh(item)
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Scheduled message not found")
        if code in ("already_processed", "invalid_send_at"):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        if code == "online_delivery_locked":
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    return _scheduled_message_response(item)


@router.post(
    "/chats/{conversation_id}/messages/{message_id}/callback",
    response_model=MessageResponse,
)
async def callback_query(
    conversation_id: int,
    message_id: int,
    body: CallbackQueryRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == current_user.id,
        )
        .first()
    )
    if not member:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    msg = (
        db.query(Message)
        .filter(
            Message.id == message_id,
            Message.conversation_id == conversation_id,
            Message.deleted_at.is_(None),
        )
        .first()
    )
    if not msg:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Message not found")
    if not msg.inline_keyboard_json:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "inline_keyboard_not_found",
        )
    from app.services.bot_handler import process_callback_for_bot

    result = process_callback_for_bot(
        db,
        conversation_id=conversation_id,
        source_message=msg,
        callback_data=body.data,
    )
    if not result:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "callback_not_found")
    bot_reply, _ = result
    bot_user = _find_chat_bot(db, conversation_id)
    if bot_user:
        AnalyticsService(db).log_event(
            event_type="bot_callback_click",
            entity_type="bot",
            entity_id=bot_user.id,
            user_id=current_user.id,
            author_id=bot_user.created_by_user_id,
            metadata={
                "data": body.data,
                "message_id": message_id,
                "conversation_id": conversation_id,
            },
        )
    _enqueue_bot_webhook(
        db,
        conversation_id=conversation_id,
        update_type="callback.query",
        payload={
            "conversation_id": conversation_id,
            "message_id": message_id,
            "data": body.data,
            "from_user_id": current_user.id,
            "bot_reply": _message_payload(bot_reply),
        },
    )
    db.commit()
    db.refresh(bot_reply)
    _emit(
        conversation_id,
        {
            "type": "message.callback",
            "message_id": message_id,
            "data": body.data,
            "from_user_id": current_user.id,
        },
    )
    _emit(
        conversation_id,
        {"type": "message.new", "message": _message_payload(bot_reply)},
    )
    _notify_chat_inbox(db, conversation_id, bot_reply.sender_id)
    conv = (
        db.query(Conversation)
        .filter(Conversation.id == conversation_id)
        .first()
    )
    peer_read = _peer_last_read_id(db, svc, conv, current_user.id) if conv else None
    sender = db.query(User).filter(User.id == bot_reply.sender_id).first()
    return _message_response(
        bot_reply,
        current_user.id,
        member.last_read_message_id if member else None,
        peer_read,
        conv,
        svc,
        sender,
        db=db,
    )


@router.post(
    "/chats/{conversation_id}/messages/{message_id}/poll/vote",
    response_model=MessageResponse,
)
async def vote_chat_poll(
    conversation_id: int,
    message_id: int,
    body: ChatPollVoteRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == current_user.id,
        )
        .first()
    )
    if not member:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")

    from app.services.chat_poll_service import vote_on_message_poll

    try:
        enriched = vote_on_message_poll(
            db, message_id, current_user.id, body.option_index
        )
        from app.models.conversation import Message

        msg = (
            db.query(Message)
            .filter(
                Message.id == message_id,
                Message.conversation_id == conversation_id,
            )
            .first()
        )
        if not msg:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Message not found")
        msg.content = enriched
        db.commit()
        db.refresh(msg)
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "not_poll_message":
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        if code in ("poll_closed", "invalid_option", "vote_locked", "invalid_poll"):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        raise

    conv = (
        db.query(Conversation)
        .filter(Conversation.id == conversation_id)
        .first()
    )
    peer_read = _peer_last_read_id(db, svc, conv, current_user.id) if conv else None
    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == current_user.id,
        )
        .first()
    )
    sender = db.query(User).filter(User.id == msg.sender_id).first()
    reactions = _reaction_summaries(svc, [msg.id], current_user.id).get(msg.id, [])
    response = _message_response(
        msg,
        current_user.id,
        member.last_read_message_id if member else None,
        peer_read,
        conv,
        svc,
        sender,
        reactions=reactions,
        db=db,
    )
    _emit(
        conversation_id,
        {"type": "message.edited", "message": response.model_dump(mode="json")},
    )
    return response


@router.post(
    "/chats/{conversation_id}/messages/{message_id}/poll/options",
    response_model=MessageResponse,
)
async def add_chat_poll_option(
    conversation_id: int,
    message_id: int,
    body: ChatPollAddOptionRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == current_user.id,
        )
        .first()
    )
    if not member:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")

    from app.services.chat_poll_service import add_option_to_message_poll

    try:
        enriched = add_option_to_message_poll(
            db, message_id, current_user.id, body.text
        )
        from app.models.conversation import Message

        msg = (
            db.query(Message)
            .filter(
                Message.id == message_id,
                Message.conversation_id == conversation_id,
            )
            .first()
        )
        if not msg:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Message not found")
        msg.content = enriched
        db.commit()
        db.refresh(msg)
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "not_poll_message":
            raise HTTPException(status.HTTP_404_NOT_FOUND, code)
        if code in (
            "poll_closed",
            "add_options_disabled",
            "empty_option",
            "duplicate_option",
            "poll_too_many_options",
            "invalid_poll",
        ):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        raise

    conv = (
        db.query(Conversation)
        .filter(Conversation.id == conversation_id)
        .first()
    )
    peer_read = _peer_last_read_id(db, svc, conv, current_user.id) if conv else None
    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == current_user.id,
        )
        .first()
    )
    sender = db.query(User).filter(User.id == msg.sender_id).first()
    reactions = _reaction_summaries(svc, [msg.id], current_user.id).get(msg.id, [])
    response = _message_response(
        msg,
        current_user.id,
        member.last_read_message_id if member else None,
        peer_read,
        conv,
        svc,
        sender,
        reactions=reactions,
        db=db,
    )
    _emit(
        conversation_id,
        {"type": "message.edited", "message": response.model_dump(mode="json")},
    )
    return response


@router.get("/chats/{conversation_id}/messages/{message_id}/poll/voters")
async def get_chat_poll_voters(
    conversation_id: int,
    message_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    from app.services.chat_poll_service import list_message_poll_voters

    try:
        return list_message_poll_voters(
            db,
            conversation_id=conversation_id,
            message_id=message_id,
            user_id=current_user.id,
        )
    except ValueError as e:
        code = str(e)
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        if code == "not_poll_message":
            raise HTTPException(status.HTTP_404_NOT_FOUND, code)
        if code == "voters_hidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, code)
        if code == "invalid_poll":
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        raise


@router.post(
    "/chats/{conversation_id}/messages/{message_id}/poll/close",
    response_model=MessageResponse,
)
async def close_chat_poll(
    conversation_id: int,
    message_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == current_user.id,
        )
        .first()
    )
    if not member:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")

    from app.services.chat_poll_service import close_message_poll

    try:
        enriched = close_message_poll(db, message_id, current_user.id)
        from app.models.conversation import Message

        msg = (
            db.query(Message)
            .filter(
                Message.id == message_id,
                Message.conversation_id == conversation_id,
            )
            .first()
        )
        if not msg:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Message not found")
        msg.content = enriched
        db.commit()
        db.refresh(msg)
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "not_poll_message":
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, code)
        if code in ("poll_already_closed", "invalid_poll"):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        raise

    conv = (
        db.query(Conversation)
        .filter(Conversation.id == conversation_id)
        .first()
    )
    peer_read = _peer_last_read_id(db, svc, conv, current_user.id) if conv else None
    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == current_user.id,
        )
        .first()
    )
    sender = db.query(User).filter(User.id == msg.sender_id).first()
    reactions = _reaction_summaries(svc, [msg.id], current_user.id).get(msg.id, [])
    response = _message_response(
        msg,
        current_user.id,
        member.last_read_message_id if member else None,
        peer_read,
        conv,
        svc,
        sender,
        reactions=reactions,
        db=db,
    )
    _emit(
        conversation_id,
        {"type": "message.edited", "message": response.model_dump(mode="json")},
    )
    return response


@router.delete("/chats/{conversation_id}/messages/{message_id}")
async def delete_message(
    conversation_id: int,
    message_id: int,
    scope: str = "all",
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        applied = svc.delete_message(
            conversation_id,
            message_id,
            current_user.id,
            scope=scope,
        )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Message not found")
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        if code == "bad_scope":
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid scope")
        if code == "too_old":
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                "Message is too old to delete for everyone",
            )
        raise
    if applied == "all":
        _emit(
            conversation_id,
            {"type": "message.deleted", "message_id": message_id},
        )
    else:
        # Only the requester should drop the bubble locally; no room fanout.
        publish_user_event(
            current_user.id,
            {
                "event": "chat.message_hidden",
                "conversation_id": conversation_id,
                "message_id": message_id,
            },
        )
    return {"ok": True, "scope": applied}


@router.patch(
    "/chats/{conversation_id}/messages/{message_id}",
    response_model=MessageResponse,
)
async def edit_message(
    conversation_id: int,
    message_id: int,
    body: EditMessageRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        msg = svc.edit_message(
            conversation_id, message_id, current_user.id, body.content
        )
        db.commit()
        db.refresh(msg)
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Message not found")
        if code in ("forbidden", "not_editable"):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        if code == "empty_message":
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        raise

    reactions = _reaction_summaries(svc, [msg.id], current_user.id).get(msg.id, [])
    _emit(
        conversation_id,
        {
            "type": "message.edited",
            "message": _message_payload(
                msg, [r.model_dump() for r in reactions]
            ),
        },
    )
    conv = (
        db.query(Conversation)
        .filter(Conversation.id == conversation_id)
        .first()
    )
    peer_read = _peer_last_read_id(db, svc, conv, current_user.id) if conv else None
    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == current_user.id,
        )
        .first()
    )
    sender = db.query(User).filter(User.id == msg.sender_id).first()
    return _message_response(
        msg,
        current_user.id,
        member.last_read_message_id if member else None,
        peer_read,
        conv,
        svc,
        sender,
        reactions=reactions,
    )


@router.get(
    "/chats/{conversation_id}/messages/{message_id}/edits",
    response_model=MessageEditHistoryResponse,
)
async def list_message_edits(
    conversation_id: int,
    message_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        msg, rows = svc.list_message_edit_history(
            conversation_id, message_id, current_user.id
        )
    except ValueError as e:
        code = str(e)
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Message not found")
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        raise
    return MessageEditHistoryResponse(
        current_content=msg.content or "",
        items=[
            MessageEditHistoryItem(
                content=row.previous_content or "",
                edited_at=row.edited_at,
                editor_id=row.editor_id,
            )
            for row in rows
        ],
    )


@router.post("/chats/translate", response_model=TranslateTextResponse)
async def translate_chat_text(
    body: TranslateTextRequest,
    current_user: User = Depends(get_current_user_required),
):
    del current_user  # auth required; no per-user state
    text = (body.text or "").strip()
    if not text:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "empty_text")
    target = (body.target_lang or "ru").strip().lower()[:8] or "ru"
    from app.api.v1.recipes import translate_text

    translated = translate_text(text, target)
    return TranslateTextResponse(
        text=text,
        translated=translated or text,
        target_lang=target,
    )


@router.post("/chats/{conversation_id}/messages/{message_id}/reactions")
async def add_message_reaction(
    conversation_id: int,
    message_id: int,
    body: MessageReactionRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        svc.set_message_reaction(
            conversation_id, message_id, current_user.id, body.emoji
        )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Message not found")
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        if code == "invalid_emoji":
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        raise
    reactions = _reaction_summaries(svc, [message_id], current_user.id).get(
        message_id, []
    )
    _emit(
        conversation_id,
        {
            "type": "message.reaction",
            "message_id": message_id,
            "reactions": [r.model_dump() for r in reactions],
        },
    )
    return {
        "ok": True,
        "message_id": message_id,
        "reactions": reactions,
    }


@router.delete("/chats/{conversation_id}/messages/{message_id}/reactions")
async def remove_message_reaction(
    conversation_id: int,
    message_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        svc.remove_message_reaction(
            conversation_id, message_id, current_user.id
        )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Message not found")
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        raise
    reactions = _reaction_summaries(svc, [message_id], current_user.id).get(
        message_id, []
    )
    _emit(
        conversation_id,
        {
            "type": "message.reaction",
            "message_id": message_id,
            "reactions": [r.model_dump() for r in reactions],
        },
    )
    return {
        "ok": True,
        "message_id": message_id,
        "reactions": reactions,
    }


@router.post("/chats/{conversation_id}/messages/{message_id}/pin")
async def pin_message(
    conversation_id: int,
    message_id: int,
    body: PinMessageRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        svc.set_pinned_message(
            conversation_id,
            current_user.id,
            message_id if body.pinned else None,
            body.pinned,
        )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code in ("not_found", "missing_message"):
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Message not found")
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        raise
    if body.pinned:
        pinned = svc.get_pinned_message(conversation_id, current_user.id)
        _emit(
            conversation_id,
            {
                "type": "message.pinned",
                "message_id": message_id,
                "message": _message_payload(pinned) if pinned else None,
            },
        )
    else:
        _emit(
            conversation_id,
            {"type": "message.unpinned", "conversation_id": conversation_id},
        )
    return {"ok": True, "pinned": body.pinned, "message_id": message_id}


@router.post("/chats/{conversation_id}/typing")
async def send_typing(
    conversation_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    if not svc._is_member(conversation_id, current_user.id):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    _emit(
        conversation_id,
        {
            "type": "typing",
            "user_id": current_user.id,
            "conversation_id": conversation_id,
        },
    )
    # Fan-out to hub list (Telegram «печатает…» in chat preview).
    member_ids = (
        db.query(ConversationMember.user_id)
        .filter(ConversationMember.conversation_id == conversation_id)
        .all()
    )
    for (uid,) in member_ids:
        if uid == current_user.id:
            continue
        publish_user_event(
            uid,
            {
                "event": "chat.typing",
                "conversation_id": conversation_id,
                "user_id": current_user.id,
            },
        )
    return {"ok": True}


@router.get("/chats/{conversation_id}/stream")
async def chat_event_stream(
    conversation_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    if not svc._is_member(conversation_id, current_user.id):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")

    async def generate():
        yield ": connected\n\n"
        try:
            event_iter = subscribe_chat_events(
                conversation_id, current_user.id
            ).__aiter__()
            while True:
                try:
                    event = await asyncio.wait_for(
                        event_iter.__anext__(), timeout=25.0
                    )
                    yield f"data: {json.dumps(event, default=str)}\n\n"
                except asyncio.TimeoutError:
                    yield ": ping\n\n"
                except StopAsyncIteration:
                    break
        except asyncio.CancelledError:
            raise
        except Exception:
            yield "data: {\"type\":\"error\"}\n\n"

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@router.post("/chats/{conversation_id}/delivered")
async def mark_delivered(
    conversation_id: int,
    body: MarkDeliveredRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        svc.mark_delivered(conversation_id, current_user.id, body.message_id)
        db.commit()
    except ValueError:
        db.rollback()
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    _emit(
        conversation_id,
        {
            "type": "message.delivered",
            "user_id": current_user.id,
            "last_delivered_message_id": body.message_id,
        },
    )
    return {"ok": True}


@router.get(
    "/chats/{conversation_id}/bot-commands",
    response_model=ChatBotCommandsResponse,
)
async def list_conversation_bot_commands(
    conversation_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Public slash-commands for the bot in this chat (command + description)."""
    svc = ChatService(db)
    if not svc._is_member(conversation_id, current_user.id):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    bot = _find_chat_bot(db, conversation_id)
    if not bot:
        return ChatBotCommandsResponse(bot_id=0, items=[])
    rows = (
        db.query(BotCommand)
        .filter(BotCommand.bot_id == bot.id)
        .order_by(BotCommand.command.asc())
        .all()
    )
    return ChatBotCommandsResponse(
        bot_id=bot.id,
        bot_username=getattr(bot, "bot_username", None) or bot.username,
        items=[
            ChatBotCommandItem(
                command=c.command,
                description=c.description or "",
            )
            for c in rows
            if (c.command or "").strip()
        ],
    )


@router.get(
    "/chats/{conversation_id}/messages/{message_id}/readers",
    response_model=MessageReadersResponse,
)
async def list_message_readers(
    conversation_id: int,
    message_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        users, other_count = svc.message_readers(
            conversation_id, message_id, current_user.id
        )
    except ValueError as e:
        code = str(e)
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Message not found")
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    return MessageReadersResponse(
        items=[MessageReaderItem(user=_brief(u)) for u in users],
        reader_count=len(users),
        other_member_count=other_count,
    )


@router.get(
    "/chats/{conversation_id}/messages/{message_id}/reactions",
    response_model=MessageReactionsDetailResponse,
)
async def list_message_reactions(
    conversation_id: int,
    message_id: int,
    emoji: Optional[str] = Query(None),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        rows = svc.message_reaction_users(
            conversation_id, message_id, current_user.id, emoji=emoji
        )
    except ValueError as e:
        code = str(e)
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Message not found")
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    return MessageReactionsDetailResponse(
        items=[
            MessageReactionUserItem(emoji=reaction_emoji, user=_brief(user))
            for reaction_emoji, user in rows
        ],
        reaction_count=len(rows),
    )


@router.post("/chats/{conversation_id}/read")
async def mark_read(
    conversation_id: int,
    body: MarkReadRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        svc.mark_read(conversation_id, current_user.id, body.message_id)
        db.commit()
    except ValueError:
        db.rollback()
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    _emit(
        conversation_id,
        {
            "type": "message.delivered",
            "user_id": current_user.id,
            "last_delivered_message_id": body.message_id,
        },
    )
    _emit(
        conversation_id,
        {
            "type": "message.read",
            "user_id": current_user.id,
            "last_read_message_id": body.message_id,
        },
    )
    return {"ok": True}


@router.post("/chats/{conversation_id}/unread")
async def mark_unread(
    conversation_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        last_read = svc.mark_unread(conversation_id, current_user.id)
        db.commit()
    except ValueError:
        db.rollback()
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    _emit(
        conversation_id,
        {
            "type": "message.unread",
            "user_id": current_user.id,
            "last_read_message_id": last_read,
        },
    )
    return {"ok": True, "last_read_message_id": last_read}


@router.delete("/chats/{conversation_id}")
async def delete_conversation(
    conversation_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        svc.delete_conversation(conversation_id, current_user.id)
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Conversation not found")
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        if code == "cannot_delete_saved":
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST, "Cannot delete saved messages chat"
            )
        raise
    return {"ok": True}


@router.post("/chats/{conversation_id}/clear-history")
async def clear_chat_history(
    conversation_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        cleared_to = svc.clear_history(conversation_id, current_user.id)
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        raise
    return {"ok": True, "cleared_before_id": cleared_to}


@router.get("/users/{peer_user_id}/common-groups")
async def list_common_groups(
    peer_user_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        groups = svc.list_common_groups(current_user.id, peer_user_id)
    except ValueError as e:
        code = str(e)
        if code == "user_not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
        raise
    items = []
    for conv in groups:
        items.append(
            {
                "id": conv.id,
                "type": conv.type,
                "title": conv.title,
                "member_count": svc._member_count(conv.id),
            }
        )
    return {"items": items}


@router.post("/chats/{conversation_id}/archive")
async def archive_chat(
    conversation_id: int,
    body: ArchiveChatRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        svc.set_archived(conversation_id, current_user.id, body.archived)
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "cannot_archive_saved":
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST, "Cannot archive saved messages chat"
            )
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    return {"ok": True, "archived": body.archived}


@router.post("/chats/{conversation_id}/pin")
async def pin_chat(
    conversation_id: int,
    body: PinChatRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        svc.set_pinned(conversation_id, current_user.id, body.pinned)
        db.commit()
    except ValueError:
        db.rollback()
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    return {"ok": True, "pinned": body.pinned}


@router.post("/chats/{conversation_id}/mute")
async def mute_chat(
    conversation_id: int,
    body: MuteChatRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        svc.set_muted(conversation_id, current_user.id, body.muted)
        db.commit()
    except ValueError:
        db.rollback()
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    return {"ok": True, "muted": body.muted}


@router.patch("/chats/{conversation_id}", response_model=ConversationResponse)
async def update_group_chat(
    conversation_id: int,
    body: UpdateGroupChatRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    notes = []
    try:
        if (
            body.title is None
            and body.only_admins_can_post is None
            and body.join_by_request_enabled is None
            and body.slow_mode_seconds is None
            and body.anti_flood_max_messages_per_minute is None
            and body.protect_content is None
        ):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "empty_patch")
        if body.title is not None:
            svc.update_group_title(conversation_id, current_user.id, body.title)
            notes.append(
                svc.create_group_system_note(
                    conversation_id,
                    current_user.id,
                    f"🛡 { _user_label(current_user) } changed group title.",
                )
            )
        if body.only_admins_can_post is not None:
            svc.set_group_only_admins_can_post(
                conversation_id,
                current_user.id,
                body.only_admins_can_post,
            )
            notes.append(
                svc.create_group_system_note(
                    conversation_id,
                    current_user.id,
                    "🛡 Sending mode changed: "
                    + (
                        "only admins can post."
                        if body.only_admins_can_post
                        else "all members can post."
                    ),
                )
            )
        if body.join_by_request_enabled is not None:
            svc.set_group_join_by_request_enabled(
                conversation_id,
                current_user.id,
                body.join_by_request_enabled,
            )
            notes.append(
                svc.create_group_system_note(
                    conversation_id,
                    current_user.id,
                    "🛡 Join mode changed: "
                    + (
                        "join requests are required."
                        if body.join_by_request_enabled
                        else "direct join by invite enabled."
                    ),
                )
            )
        if body.slow_mode_seconds is not None:
            svc.set_group_slow_mode_seconds(
                conversation_id,
                current_user.id,
                body.slow_mode_seconds,
            )
            notes.append(
                svc.create_group_system_note(
                    conversation_id,
                    current_user.id,
                    "🛡 Slow mode changed: "
                    + (
                        "disabled."
                        if int(body.slow_mode_seconds) <= 0
                        else f"{int(body.slow_mode_seconds)} sec between messages."
                    ),
                )
            )
        if body.anti_flood_max_messages_per_minute is not None:
            svc.set_group_anti_flood_limit(
                conversation_id,
                current_user.id,
                body.anti_flood_max_messages_per_minute,
            )
            notes.append(
                svc.create_group_system_note(
                    conversation_id,
                    current_user.id,
                    "🛡 Anti-flood changed: "
                    + (
                        "disabled."
                        if int(body.anti_flood_max_messages_per_minute) <= 0
                        else f"max {int(body.anti_flood_max_messages_per_minute)} messages/min."
                    ),
                )
            )
        if body.protect_content is not None:
            svc.set_group_protect_content(
                conversation_id,
                current_user.id,
                body.protect_content,
            )
            notes.append(
                svc.create_group_system_note(
                    conversation_id,
                    current_user.id,
                    "🛡 Content protection: "
                    + (
                        "enabled (forwarding restricted)."
                        if body.protect_content
                        else "disabled."
                    ),
                )
            )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Conversation not found")
        if code == "not_group":
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "Not a group chat")
        if code in ("forbidden", "empty_title"):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        raise
    row = svc.get_conversation_row(conversation_id, current_user.id)
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Conversation not found")
    item = _conversation_response(row, svc, db, current_user)
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Conversation not found")
    for note in notes:
        _emit(
            conversation_id,
            {"type": "message.new", "message": _message_payload(note)},
        )
    if notes:
        _notify_chat_inbox(db, conversation_id, current_user.id)
    return item


@router.post("/chats/{conversation_id}/members")
async def add_group_members(
    conversation_id: int,
    body: AddGroupMembersRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        added = svc.add_group_members(
            conversation_id, current_user.id, body.user_ids
        )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "user_not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
        if code == "user_blocked":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "User blocked")
        if code == "group_member_banned":
            raise HTTPException(status.HTTP_403_FORBIDDEN, code)
        if code in ("forbidden", "not_group"):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        raise
    return {"ok": True, "added": added}


@router.delete("/chats/{conversation_id}/members/{member_user_id}")
async def remove_group_member(
    conversation_id: int,
    member_user_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        svc.remove_group_member(
            conversation_id, current_user.id, member_user_id
        )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Member not found")
        if code in ("forbidden", "not_group"):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        raise
    return {"ok": True}


@router.patch("/chats/{conversation_id}/members/{member_user_id}/admin")
async def set_group_member_admin(
    conversation_id: int,
    member_user_id: int,
    body: GroupMemberAdminRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    note = None
    try:
        svc.set_group_member_admin(
            conversation_id=conversation_id,
            actor_id=current_user.id,
            target_user_id=member_user_id,
            is_admin=body.is_admin,
        )
        target_user = db.query(User).filter(User.id == member_user_id).first()
        note = svc.create_group_system_note(
            conversation_id,
            current_user.id,
            "🛡 "
            + _user_label(current_user)
            + (" granted moderator role to " if body.is_admin else " revoked moderator role from ")
            + _user_label(target_user, member_user_id)
            + ".",
        )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Member not found")
        if code == "cannot_change_self_role":
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        if code in ("forbidden", "not_group"):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        raise
    if note is not None:
        _emit(
            conversation_id,
            {"type": "message.new", "message": _message_payload(note)},
        )
        _notify_chat_inbox(db, conversation_id, current_user.id)
    return {"ok": True}


@router.patch("/chats/{conversation_id}/members/{member_user_id}/permissions")
async def set_group_member_permissions(
    conversation_id: int,
    member_user_id: int,
    body: GroupMemberPermissionsRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    note = None
    try:
        svc.set_group_member_permissions(
            conversation_id=conversation_id,
            actor_id=current_user.id,
            target_user_id=member_user_id,
            can_manage_members=body.can_manage_members,
            can_manage_posting_permissions=body.can_manage_posting_permissions,
        )
        target_user = db.query(User).filter(User.id == member_user_id).first()
        scopes = []
        if body.can_manage_members:
            scopes.append("members")
        if body.can_manage_posting_permissions:
            scopes.append("chat settings")
        scope_text = ", ".join(scopes) if scopes else "no extra scopes"
        note = svc.create_group_system_note(
            conversation_id,
            current_user.id,
            f"🛡 {_user_label(current_user)} updated moderator permissions for "
            f"{_user_label(target_user, member_user_id)} ({scope_text}).",
        )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Member not found")
        if code in ("cannot_change_self_role", "target_not_admin"):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        if code in ("forbidden", "not_group"):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        raise
    if note is not None:
        _emit(
            conversation_id,
            {"type": "message.new", "message": _message_payload(note)},
        )
        _notify_chat_inbox(db, conversation_id, current_user.id)
    return {"ok": True}


@router.patch("/chats/{conversation_id}/members/{member_user_id}/send-restriction")
async def set_group_member_send_restriction(
    conversation_id: int,
    member_user_id: int,
    body: GroupMemberSendRestrictionRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    note = None
    try:
        svc.set_group_member_send_restriction(
            conversation_id=conversation_id,
            actor_id=current_user.id,
            target_user_id=member_user_id,
            send_restricted=body.send_restricted,
            send_restricted_until=body.send_restricted_until,
            reason=body.reason,
        )
        target_user = db.query(User).filter(User.id == member_user_id).first()
        if body.send_restricted:
            suffix = ""
            if body.send_restricted_until is not None:
                suffix = f" until {body.send_restricted_until.isoformat()}"
            note = svc.create_group_system_note(
                conversation_id,
                current_user.id,
                f"🛡 {_user_label(current_user)} restricted messaging for "
                f"{_user_label(target_user, member_user_id)}{suffix}.",
            )
        else:
            note = svc.create_group_system_note(
                conversation_id,
                current_user.id,
                f"🛡 {_user_label(current_user)} removed messaging restriction for "
                f"{_user_label(target_user, member_user_id)}.",
            )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Member not found")
        if code in (
            "cannot_restrict_self",
            "cannot_restrict_creator",
            "cannot_restrict_admin",
            "invalid_restriction_until",
        ):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        if code in ("forbidden", "not_group"):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        raise
    if note is not None:
        _emit(
            conversation_id,
            {"type": "message.new", "message": _message_payload(note)},
        )
        _notify_chat_inbox(db, conversation_id, current_user.id)
    return {"ok": True}


@router.get("/chats/{conversation_id}/bans", response_model=GroupMemberBanListResponse)
async def list_group_bans(
    conversation_id: int,
    limit: int = Query(200, ge=1, le=500),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        rows = svc.list_group_bans(conversation_id, current_user.id, limit=limit)
    except ValueError:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    return GroupMemberBanListResponse(
        items=[_group_ban_response(r) for r in rows],
    )


@router.post("/chats/{conversation_id}/bans/{target_user_id}")
async def ban_group_member(
    conversation_id: int,
    target_user_id: int,
    body: GroupMemberBanRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    note = None
    try:
        svc.ban_group_member(
            conversation_id=conversation_id,
            actor_id=current_user.id,
            target_user_id=target_user_id,
            reason=body.reason,
            banned_until=body.banned_until,
        )
        target_user = db.query(User).filter(User.id == target_user_id).first()
        note = svc.create_group_system_note(
            conversation_id,
            current_user.id,
            f"🛡 {_user_label(current_user)} banned "
            f"{_user_label(target_user, target_user_id)} from the group.",
        )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "user_not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
        if code in (
            "cannot_ban_self",
            "cannot_ban_creator",
            "cannot_ban_admin",
            "invalid_ban_until",
        ):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        if code in ("forbidden", "not_group"):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        raise
    if note is not None:
        _emit(
            conversation_id,
            {"type": "message.new", "message": _message_payload(note)},
        )
        _notify_chat_inbox(db, conversation_id, current_user.id)
    return {"ok": True}


@router.delete("/chats/{conversation_id}/bans/{target_user_id}")
async def unban_group_member(
    conversation_id: int,
    target_user_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    note = None
    try:
        svc.unban_group_member(
            conversation_id=conversation_id,
            actor_id=current_user.id,
            target_user_id=target_user_id,
        )
        target_user = db.query(User).filter(User.id == target_user_id).first()
        note = svc.create_group_system_note(
            conversation_id,
            current_user.id,
            f"🛡 {_user_label(current_user)} unbanned "
            f"{_user_label(target_user, target_user_id)}.",
        )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Ban not found")
        if code in ("forbidden", "not_group"):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        raise
    if note is not None:
        _emit(
            conversation_id,
            {"type": "message.new", "message": _message_payload(note)},
        )
        _notify_chat_inbox(db, conversation_id, current_user.id)
    return {"ok": True}


@router.get(
    "/chats/{conversation_id}/join-requests",
    response_model=GroupJoinRequestListResponse,
)
async def list_group_join_requests(
    conversation_id: int,
    status_filter: str = Query("pending", alias="status"),
    limit: int = Query(200, ge=1, le=500),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        rows = svc.list_group_join_requests(
            conversation_id,
            current_user.id,
            status_filter=status_filter,
            limit=limit,
        )
        db.commit()
    except ValueError:
        db.rollback()
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    return GroupJoinRequestListResponse(
        items=[_group_join_request_response(r) for r in rows]
    )


@router.patch("/chats/{conversation_id}/join-requests/{request_id}")
async def review_group_join_request(
    conversation_id: int,
    request_id: int,
    body: GroupJoinRequestReviewRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    note = None
    requester_user_id: Optional[int] = None
    try:
        row = svc.review_group_join_request(
            conversation_id,
            current_user.id,
            request_id,
            approve=body.approve,
        )
        requester_user_id = row.user_id
        requester_user = db.query(User).filter(User.id == requester_user_id).first()
        note = svc.create_group_system_note(
            conversation_id,
            current_user.id,
            f"🛡 {_user_label(current_user)} "
            + ("approved join request from " if body.approve else "rejected join request from ")
            + _user_label(requester_user, requester_user_id)
            + ".",
        )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Request not found")
        if code in ("already_reviewed", "group_member_banned"):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        if code in ("forbidden", "not_group"):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        raise
    if note is not None:
        _emit(
            conversation_id,
            {"type": "message.new", "message": _message_payload(note)},
        )
        _notify_chat_inbox(db, conversation_id, current_user.id)
    if requester_user_id is not None:
        publish_user_event(
            requester_user_id,
            {
                "event": "chat.join_request.reviewed",
                "conversation_id": conversation_id,
                "approved": bool(body.approve),
            },
        )
    return {"ok": True}


@router.get("/chats/join-requests/inbox", response_model=JoinRequestsInboxResponse)
async def list_join_requests_inbox(
    limit: int = Query(200, ge=1, le=500),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    rows = svc.list_join_requests_inbox(current_user.id, limit=limit)
    items: List[JoinRequestsInboxItemResponse] = []
    for row in rows:
        conv_row = svc.get_conversation_row(row["conversation_id"], current_user.id)
        if not conv_row:
            continue
        conv_item = _conversation_response(conv_row, svc, db, current_user)
        if not conv_item:
            continue
        items.append(
            JoinRequestsInboxItemResponse(
                id=row["id"],
                conversation=conv_item,
                user=_brief(row["user"]),
                status=row["status"],
                requested_at=row["requested_at"],
            )
        )
    return JoinRequestsInboxResponse(items=items)


@router.get(
    "/chats/{conversation_id}/moderation-log",
    response_model=GroupModerationLogResponse,
)
async def list_group_moderation_log(
    conversation_id: int,
    action: str = Query("all"),
    limit: int = Query(200, ge=1, le=500),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        rows = svc.list_group_moderation_log(
            conversation_id,
            current_user.id,
            action_filter=action,
            limit=limit,
        )
    except ValueError:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    if not rows:
        return GroupModerationLogResponse(items=[])
    actor_ids = {m.sender_id for m in rows}
    actors = (
        {u.id: u for u in db.query(User).filter(User.id.in_(actor_ids)).all()}
        if actor_ids
        else {}
    )
    return GroupModerationLogResponse(
        items=[
            GroupModerationLogItemResponse(
                id=m.id,
                action=_moderation_action_from_text(m.content),
                text=m.content,
                created_at=m.created_at,
                actor=_brief(actors[m.sender_id]) if m.sender_id in actors else None,
            )
            for m in rows
        ]
    )


@router.post("/chats/{conversation_id}/leave")
async def leave_group_chat(
    conversation_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        svc.leave_group(conversation_id, current_user.id)
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code in ("forbidden", "not_group", "not_found"):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        raise
    return {"ok": True}


@router.get("/contacts", response_model=ContactListResponse)
async def list_contacts(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    rows = svc.list_contacts(current_user.id)
    items = []
    for row in rows:
        user = db.query(User).filter(User.id == row.contact_user_id).first()
        if user:
            items.append(
                ContactResponse(id=row.id, user=_brief(user), created_at=row.created_at)
            )
    return ContactListResponse(items=items)


@router.post("/contacts", response_model=ContactResponse)
async def add_contact(
    body: AddContactRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        row = svc.add_contact(current_user.id, body.user_id)
        db.commit()
        db.refresh(row)
    except ValueError as e:
        db.rollback()
        if str(e) == "user_not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
        if str(e) == "self_contact":
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "Cannot add yourself")
        raise
    user = db.query(User).filter(User.id == row.contact_user_id).first()
    return ContactResponse(id=row.id, user=_brief(user), created_at=row.created_at)


@router.post("/contacts/phone-sync", response_model=PhoneSyncResponse)
async def sync_phone_contacts(
    body: PhoneSyncRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Найти пользователей HAN Eat по хешам номеров из адресной книги."""
    svc = ChatService(db)
    rows = svc.match_users_by_phone_hashes(
        current_user.id,
        body.phone_hashes,
    )
    items = [
        PhoneContactMatchItem(
            id=r["user"].id,
            name=r["user"].name,
            username=r["user"].username,
            avatar_url=r["user"].avatar_url,
            is_contact=r["is_contact"],
            phone_hash=r["user"].phone_hash,
        )
        for r in rows
    ]
    return PhoneSyncResponse(items=items)


@router.delete("/contacts/{contact_user_id}")
async def remove_contact(
    contact_user_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    ok = svc.remove_contact(current_user.id, contact_user_id)
    db.commit()
    if not ok:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Contact not found")
    return {"ok": True}


# User search lives in users.router at GET /api/v1/users/search (before /{user_id}).
