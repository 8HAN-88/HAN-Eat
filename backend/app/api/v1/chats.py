"""API личных чатов и контактов."""
import asyncio
import json
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import StreamingResponse
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
    CreateGroupChatRequest,
    CreateChatFolderRequest,
    ChatFolderItemRequest,
    ChatFolderListResponse,
    ChatFolderResponse,
    ReorderChatFoldersRequest,
    DirectChatRequest,
    EditMessageRequest,
    MarkReadRequest,
    MessageReactionRequest,
    MessageReactionSummary,
    MuteChatRequest,
    PinChatRequest,
    UpdateGroupChatRequest,
    UpdateChatFolderRequest,
    MessageListResponse,
    MessageResponse,
    PhoneContactMatchItem,
    PinMessageRequest,
    PhoneSyncRequest,
    PhoneSyncResponse,
    SendMessageRequest,
    ChatPollVoteRequest,
)
from app.models.conversation import Conversation, ConversationMember
from app.services.chat_event_bus import publish as publish_chat_event
from app.services.chat_event_bus import subscribe as subscribe_chat_events
from app.services.chat_service import ChatService
from app.services.user_event_bus import publish_user_event

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
    return {
        "id": msg.id,
        "conversation_id": msg.conversation_id,
        "sender_id": msg.sender_id,
        "type": msg.type,
        "content": msg.content,
        "media_url": msg.media_url,
        "reply_to_message_id": msg.reply_to_message_id,
        "created_at": msg.created_at.isoformat() if msg.created_at else None,
        "edited_at": msg.edited_at.isoformat() if getattr(msg, "edited_at", None) else None,
        "reactions": reactions or [],
    }


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


def _brief(user: User) -> ChatUserBrief:
    return ChatUserBrief(
        id=user.id,
        name=user.name,
        username=user.username,
        avatar_url=user.avatar_url,
        last_seen_at=user.last_seen_at,
    )


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


def _sender_name(user: Optional[User]) -> Optional[str]:
    if not user:
        return None
    return user.name or user.username


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
    content = msg.content
    if db is not None and getattr(msg, "type", None) == "poll":
        content = _enriched_content(db, msg, current_user_id, poll_content_cache)
    return MessageResponse(
        id=msg.id,
        conversation_id=msg.conversation_id,
        sender_id=msg.sender_id,
        sender_name=_sender_name(sender),
        type=msg.type,
        content=content,
        media_url=msg.media_url,
        reply_to_message_id=msg.reply_to_message_id,
        created_at=msg.created_at,
        edited_at=getattr(msg, "edited_at", None),
        is_mine=is_mine,
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
    peer_read = _peer_last_read_id(db, svc, conv, current_user.id)
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
        )
    return ConversationResponse(
        id=conv.id,
        type=conv.type,
        peer=_brief(peer) if peer else None,
        title=conv.title if conv.type in ("group", "saved") else None,
        member_count=row.get("member_count", 0),
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
    )


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
        users = svc.list_members(conversation_id, current_user.id)
    except ValueError:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    return ConversationMembersResponse(items=[_brief(u) for u in users])


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


@router.post("/chats/{conversation_id}/messages", response_model=MessageResponse)
async def send_message(
    conversation_id: int,
    body: SendMessageRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    content = body.content
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
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        if code in ("empty_message", "missing_media", "empty_poll", "invalid_reply"):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        if code == "user_blocked":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "User blocked")
        raise

    if is_new:
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
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = ChatService(db)
    try:
        svc.delete_message(conversation_id, message_id, current_user.id)
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Message not found")
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
        raise
    _emit(
        conversation_id,
        {"type": "message.deleted", "message_id": message_id},
    )
    return {"ok": True}


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
    try:
        svc.update_group_title(conversation_id, current_user.id, body.title)
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
