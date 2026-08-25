"""Сервис личных чатов и контактов."""
from __future__ import annotations

import json
import secrets
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional, Tuple

from sqlalchemy import and_, func, or_
from sqlalchemy.orm import Session, joinedload

from app.models.conversation import (
    Contact,
    Conversation,
    ConversationDraft,
    ConversationMember,
    ConversationPinnedMessage,
    GroupInviteLink,
    GroupMemberBan,
    GroupJoinRequest,
    Message,
    MessageEditHistory,
    MessageHide,
    MessageReaction,
    ScheduledMessage,
)
from app.models.forum_topic import ForumTopic
from app.models.chat_folder import ChatFolder, ChatFolderItem
from app.models.chat_folder_share import ChatFolderShare
from app.models.user import User
from app.models.user_block import UserBlock
from app.services.notification_service import NotificationService


def _inline_keyboard_text_parts(inline_keyboard_json: Optional[str]) -> List[str]:
    if not inline_keyboard_json:
        return []
    try:
        source = json.loads(inline_keyboard_json)
    except Exception:
        return []
    if not isinstance(source, list):
        return []
    parts: List[str] = []
    for row in source:
        if not isinstance(row, list):
            continue
        for btn in row:
            if not isinstance(btn, dict):
                continue
            text = str(btn.get("text") or "").strip()
            if text:
                parts.append(text)
            callback_text = str(btn.get("callback_text") or "").strip()
            if callback_text:
                parts.append(callback_text)
    return parts


class ChatService:
    def __init__(self, db: Session):
        self.db = db

    def _pair_ids(self, a: int, b: int) -> Tuple[int, int]:
        return (a, b) if a < b else (b, a)

    def _get_user_or_404(self, user_id: int) -> User:
        user = (
            self.db.query(User)
            .filter(User.id == user_id, User.deleted_at.is_(None), User.banned_at.is_(None))
            .first()
        )
        if not user:
            raise ValueError("user_not_found")
        return user

    def _is_member(self, conversation_id: int, user_id: int) -> bool:
        return (
            self.db.query(ConversationMember.id)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == user_id,
            )
            .first()
            is not None
        )

    def _cleanup_expired_group_bans(self, conversation_id: int) -> None:
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        expired = (
            self.db.query(GroupMemberBan)
            .filter(
                GroupMemberBan.conversation_id == conversation_id,
                GroupMemberBan.banned == True,  # noqa: E712
                GroupMemberBan.banned_until.isnot(None),
                GroupMemberBan.banned_until <= now,
            )
            .all()
        )
        for row in expired:
            row.banned = False
            row.banned_until = None
            row.reason = None

    def _generate_unique_group_invite_token(self) -> str:
        for _ in range(10):
            token = secrets.token_urlsafe(18).replace("-", "").replace("_", "")
            exists = self.db.query(GroupInviteLink.id).filter(
                GroupInviteLink.token == token
            ).first()
            if not exists:
                return token
        raise ValueError("invite_token_generation_failed")

    def _cleanup_expired_invite_links(self, conversation_id: int) -> None:
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        rows = (
            self.db.query(GroupInviteLink)
            .filter(
                GroupInviteLink.conversation_id == conversation_id,
                GroupInviteLink.revoked_at.is_(None),
                GroupInviteLink.expires_at.isnot(None),
                GroupInviteLink.expires_at <= now,
            )
            .all()
        )
        for row in rows:
            row.revoked_at = now

    def _is_group_member_banned(self, conversation_id: int, user_id: int) -> bool:
        self._cleanup_expired_group_bans(conversation_id)
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        row = (
            self.db.query(GroupMemberBan)
            .filter(
                GroupMemberBan.conversation_id == conversation_id,
                GroupMemberBan.user_id == user_id,
                GroupMemberBan.banned == True,  # noqa: E712
            )
            .first()
        )
        if not row:
            return False
        if row.banned_until is not None and row.banned_until <= now:
            row.banned = False
            row.banned_until = None
            row.reason = None
            return False
        return True

    def has_block_between(self, user_a: int, user_b: int) -> bool:
        if user_a == user_b:
            return False
        return (
            self.db.query(UserBlock.id)
            .filter(
                or_(
                    and_(
                        UserBlock.blocker_user_id == user_a,
                        UserBlock.blocked_user_id == user_b,
                    ),
                    and_(
                        UserBlock.blocker_user_id == user_b,
                        UserBlock.blocked_user_id == user_a,
                    ),
                )
            )
            .first()
            is not None
        )

    def get_or_create_direct(self, current_user_id: int, peer_user_id: int) -> Conversation:
        if current_user_id == peer_user_id:
            raise ValueError("self_chat")
        peer = self._get_user_or_404(peer_user_id)
        if self.has_block_between(current_user_id, peer_user_id):
            raise ValueError("user_blocked")
        low, high = self._pair_ids(current_user_id, peer_user_id)

        conv = (
            self.db.query(Conversation)
            .filter(
                Conversation.type == "direct",
                Conversation.direct_user_low_id == low,
                Conversation.direct_user_high_id == high,
            )
            .first()
        )
        if conv is None:
            from app.services.business_profile_service import can_start_dm

            if not can_start_dm(self.db, current_user_id, peer):
                raise ValueError("dm_privacy_denied")
        if conv:
            for uid in (low, high):
                existing = (
                    self.db.query(ConversationMember)
                    .filter(
                        ConversationMember.conversation_id == conv.id,
                        ConversationMember.user_id == uid,
                    )
                    .first()
                )
                if not existing:
                    self.db.add(
                        ConversationMember(conversation_id=conv.id, user_id=uid)
                    )
            self.db.flush()
            return conv

        conv = Conversation(
            type="direct",
            direct_user_low_id=low,
            direct_user_high_id=high,
        )
        self.db.add(conv)
        self.db.flush()

        for uid in (low, high):
            self.db.add(
                ConversationMember(conversation_id=conv.id, user_id=uid)
            )
        self.db.flush()
        self._archive_new_non_contact_chat(conv, initiator_id=current_user_id)
        return conv

    def get_or_create_saved(self, user_id: int) -> Conversation:
        """Личное хранилище пользователя (аналог Saved Messages)."""
        self._get_user_or_404(user_id)
        conv = (
            self.db.query(Conversation)
            .join(
                ConversationMember,
                ConversationMember.conversation_id == Conversation.id,
            )
            .filter(
                Conversation.type == "saved",
                ConversationMember.user_id == user_id,
            )
            .first()
        )
        if conv:
            return conv

        conv = Conversation(
            type="saved",
            title="Избранное",
            created_by_user_id=user_id,
        )
        self.db.add(conv)
        self.db.flush()
        self.db.add(
            ConversationMember(conversation_id=conv.id, user_id=user_id)
        )
        self.db.flush()
        return conv

    def _archive_new_non_contact_chat(
        self, conv: Conversation, initiator_id: int
    ) -> None:
        if conv.type != "direct":
            return
        recipient_id = (
            conv.direct_user_high_id
            if conv.direct_user_low_id == initiator_id
            else conv.direct_user_low_id
        )
        recipient = self.db.query(User).filter(User.id == recipient_id).first()
        if not recipient or not bool(getattr(recipient, "archive_non_contacts", False)):
            return
        from app.services.last_seen_privacy import is_owner_contact
        from app.services.subscription_service import SubscriptionService

        if not SubscriptionService(self.db).has_feature(
            recipient_id, "archive_non_contacts"
        ):
            return
        if is_owner_contact(self.db, recipient_id, initiator_id):
            return
        self.set_archived(conv.id, recipient_id, True)
        self.set_muted(conv.id, recipient_id, True)

    def peer_user_id(self, conv: Conversation, current_user_id: int) -> int:
        if conv.type != "direct":
            raise ValueError("not_direct")
        if conv.direct_user_low_id == current_user_id:
            return conv.direct_user_high_id
        return conv.direct_user_low_id

    def _member_count(self, conversation_id: int) -> int:
        return (
            self.db.query(func.count(ConversationMember.id))
            .filter(ConversationMember.conversation_id == conversation_id)
            .scalar()
            or 0
        )

    def _members_preview(self, conversation_id: int, limit: int = 4) -> List[User]:
        rows = (
            self.db.query(ConversationMember)
            .filter(ConversationMember.conversation_id == conversation_id)
            .order_by(ConversationMember.joined_at.asc())
            .limit(limit)
            .all()
        )
        ids = [r.user_id for r in rows]
        if not ids:
            return []
        users = self.db.query(User).filter(User.id.in_(ids)).all()
        by_id = {u.id: u for u in users}
        return [by_id[i] for i in ids if i in by_id]

    def list_members(self, conversation_id: int, user_id: int) -> List[dict]:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        if not conv:
            raise ValueError("forbidden")
        rows = (
            self.db.query(ConversationMember)
            .filter(ConversationMember.conversation_id == conversation_id)
            .order_by(ConversationMember.joined_at.asc())
            .all()
        )
        ids = [r.user_id for r in rows]
        if not ids:
            return []
        users = self.db.query(User).filter(User.id.in_(ids)).all()
        by_id = {u.id: u for u in users}
        member_by_user_id = {r.user_id: r for r in rows}
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        return [
            {
                "user": by_id[i],
                "is_group_admin": bool(member_by_user_id[i].is_admin),
                "is_group_creator": conv.created_by_user_id == i,
                "can_manage_members": bool(
                    member_by_user_id[i].can_manage_members
                ),
                "can_manage_posting_permissions": bool(
                    member_by_user_id[i].can_manage_posting_permissions
                ),
                "can_change_info": bool(
                    getattr(member_by_user_id[i], "can_change_info", False)
                ),
                "can_delete_messages": bool(
                    getattr(member_by_user_id[i], "can_delete_messages", False)
                ),
                "can_pin_messages": bool(
                    getattr(member_by_user_id[i], "can_pin_messages", False)
                ),
                "can_invite_users": bool(
                    getattr(member_by_user_id[i], "can_invite_users", False)
                ),
                "can_manage_video_chats": bool(
                    getattr(
                        member_by_user_id[i], "can_manage_video_chats", False
                    )
                ),
                "send_restricted": bool(
                    member_by_user_id[i].send_restricted
                    and (
                        member_by_user_id[i].send_restricted_until is None
                        or member_by_user_id[i].send_restricted_until > now
                    )
                ),
                "send_restricted_until": member_by_user_id[i].send_restricted_until,
                "send_restriction_reason": member_by_user_id[i].send_restriction_reason,
            }
            for i in ids
            if i in by_id
        ]

    def create_group(
        self, creator_id: int, title: str, member_ids: List[int]
    ) -> Conversation:
        clean_title = title.strip()
        if not clean_title:
            raise ValueError("empty_title")
        from app.services.emoji_pack_service import EmojiPackService

        EmojiPackService(self.db).require_send_tokens(creator_id, clean_title)
        others = {uid for uid in member_ids if uid != creator_id}
        if not others:
            raise ValueError("need_members")
        for uid in others:
            target = self._get_user_or_404(uid)
            if self.has_block_between(creator_id, uid):
                raise ValueError("user_blocked")
            from app.services.group_add_privacy import can_add_user_to_group

            if not can_add_user_to_group(self.db, creator_id, target):
                raise ValueError("group_add_privacy_denied")

        conv = Conversation(
            type="group",
            title=clean_title[:120],
            created_by_user_id=creator_id,
        )
        self.db.add(conv)
        self.db.flush()
        all_ids = others | {creator_id}
        for uid in all_ids:
            is_creator = uid == creator_id
            self.db.add(
                ConversationMember(
                    conversation_id=conv.id,
                    user_id=uid,
                    is_admin=is_creator,
                    can_manage_members=is_creator,
                    can_manage_posting_permissions=is_creator,
                    can_change_info=is_creator,
                    can_delete_messages=is_creator,
                    can_pin_messages=is_creator,
                    can_invite_users=is_creator,
                    can_manage_video_chats=is_creator,
                )
            )
        self.db.flush()
        return conv

    def _get_member_record(
        self, conversation_id: int, user_id: int
    ) -> Optional[ConversationMember]:
        return (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == user_id,
            )
            .first()
        )

    def _is_group_admin(self, conversation_id: int, user_id: int) -> bool:
        conv = self._get_group_or_error(conversation_id)
        if conv.created_by_user_id == user_id:
            return True
        member = self._get_member_record(conversation_id, user_id)
        return bool(member and member.is_admin)

    def _has_group_admin_right(
        self, conversation_id: int, user_id: int, right: str
    ) -> bool:
        """Creator always has every right; admins need the matching flag."""
        conv = self._get_group_or_error(conversation_id)
        if conv.created_by_user_id == user_id:
            return True
        member = self._get_member_record(conversation_id, user_id)
        if not member or not member.is_admin:
            return False
        return bool(getattr(member, right, False))

    def _can_manage_group_members(self, conversation_id: int, user_id: int) -> bool:
        return self._has_group_admin_right(
            conversation_id, user_id, "can_manage_members"
        )

    def group_member_manager_user_ids(self, conversation_id: int) -> List[int]:
        conv = self._get_group_or_error(conversation_id)
        rows = (
            self.db.query(ConversationMember.user_id)
            .filter(ConversationMember.conversation_id == conversation_id)
            .all()
        )
        member_ids = {uid for (uid,) in rows}
        manager_ids: set[int] = set()
        for uid in member_ids:
            if self._can_manage_group_members(conversation_id, uid):
                manager_ids.add(uid)
        if conv.created_by_user_id:
            manager_ids.add(conv.created_by_user_id)
        return list(manager_ids)

    def _can_manage_group_posting_permissions(
        self, conversation_id: int, user_id: int
    ) -> bool:
        return self._has_group_admin_right(
            conversation_id, user_id, "can_manage_posting_permissions"
        )

    def _can_change_group_info(self, conversation_id: int, user_id: int) -> bool:
        return self._has_group_admin_right(
            conversation_id, user_id, "can_change_info"
        )

    def _can_delete_group_messages(
        self, conversation_id: int, user_id: int
    ) -> bool:
        return self._has_group_admin_right(
            conversation_id, user_id, "can_delete_messages"
        )

    def _can_pin_group_messages(
        self, conversation_id: int, user_id: int
    ) -> bool:
        return self._has_group_admin_right(
            conversation_id, user_id, "can_pin_messages"
        )

    def _can_invite_group_users(
        self, conversation_id: int, user_id: int
    ) -> bool:
        return self._has_group_admin_right(
            conversation_id, user_id, "can_invite_users"
        )

    def _can_manage_group_video_chats(
        self, conversation_id: int, user_id: int
    ) -> bool:
        return self._has_group_admin_right(
            conversation_id, user_id, "can_manage_video_chats"
        )

    def can_manage_group_video_chats(
        self, conversation_id: int, user_id: int
    ) -> bool:
        """Public helper for CallService / API layers."""
        try:
            return self._can_manage_group_video_chats(conversation_id, user_id)
        except ValueError:
            return False

    def _is_member_send_restricted(
        self, conversation_id: int, user_id: int
    ) -> tuple[bool, Optional[datetime], Optional[str]]:
        member = self._get_member_record(conversation_id, user_id)
        if not member:
            return False, None, None
        if not member.send_restricted:
            return False, None, None
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        until = member.send_restricted_until
        if until is not None and until <= now:
            member.send_restricted = False
            member.send_restricted_until = None
            member.send_restriction_reason = None
            return False, None, None
        return True, until, member.send_restriction_reason

    def member_send_restriction_state(
        self, conversation_id: int, user_id: int
    ) -> tuple[bool, Optional[datetime], Optional[str]]:
        return self._is_member_send_restricted(conversation_id, user_id)

    def set_archived(
        self, conversation_id: int, user_id: int, archived: bool
    ) -> None:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        if conv and conv.type == "saved":
            raise ValueError("cannot_archive_saved")
        member = (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == user_id,
            )
            .first()
        )
        if not member:
            raise ValueError("forbidden")
        member.archived_at = (
            datetime.now(timezone.utc).replace(tzinfo=None) if archived else None
        )

    def message_readers(
        self, conversation_id: int, message_id: int, viewer_id: int
    ) -> tuple[list[User], int, dict]:
        """Users (excluding sender) who have read up to this message."""
        if not self._is_member(conversation_id, viewer_id):
            raise ValueError("forbidden")
        msg = (
            self.db.query(Message)
            .filter(
                Message.id == message_id,
                Message.conversation_id == conversation_id,
                Message.deleted_at.is_(None),
            )
            .first()
        )
        if not msg:
            raise ValueError("not_found")
        # Only sender (or any member) can inspect reads; keep open to members.
        others = (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id != msg.sender_id,
            )
            .all()
        )
        other_count = len(others)
        reader_rows = [
            m
            for m in others
            if m.last_read_message_id is not None
            and m.last_read_message_id >= message_id
        ]
        reader_ids = [m.user_id for m in reader_rows]
        read_at_by_user = {
            int(m.user_id): getattr(m, "last_read_at", None) for m in reader_rows
        }
        if not reader_ids:
            return [], other_count, {}
        users = (
            self.db.query(User)
            .filter(
                User.id.in_(reader_ids),
                User.deleted_at.is_(None),
            )
            .all()
        )
        by_id = {u.id: u for u in users}
        ordered = [by_id[uid] for uid in reader_ids if uid in by_id]
        return ordered, other_count, read_at_by_user

    def other_member_read_cursors(
        self, conversation_id: int, exclude_user_id: int
    ) -> list:
        """last_read_message_id for every member except exclude_user_id."""
        others = (
            self.db.query(ConversationMember.last_read_message_id)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id != exclude_user_id,
            )
            .all()
        )
        return [row[0] for row in others]

    def group_read_count(
        self, conversation_id: int, message_id: int, sender_id: int
    ) -> tuple[int, int]:
        """(readers_among_others, other_member_count) for a group message."""
        cursors = self.other_member_read_cursors(conversation_id, sender_id)
        other_count = len(cursors)
        if other_count == 0:
            return 0, 0
        read_count = sum(
            1 for c in cursors if c is not None and int(c) >= message_id
        )
        return read_count, other_count

    def group_all_read(
        self, conversation_id: int, message_id: int, sender_id: int
    ) -> bool:
        read_count, other_count = self.group_read_count(
            conversation_id, message_id, sender_id
        )
        return other_count > 0 and read_count == other_count

    def group_all_delivered(
        self, conversation_id: int, message_id: int, sender_id: int
    ) -> bool:
        others = (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id != sender_id,
            )
            .all()
        )
        if not others:
            return False
        return all(
            (
                (m.last_delivered_message_id is not None
                 and m.last_delivered_message_id >= message_id)
                or (m.last_read_message_id is not None
                    and m.last_read_message_id >= message_id)
            )
            for m in others
        )

    def list_conversations(
        self, user_id: int, *, archived_only: bool = False
    ) -> List[dict]:
        self.get_or_create_saved(user_id)
        memberships = (
            self.db.query(ConversationMember)
            .filter(ConversationMember.user_id == user_id)
            .all()
        )
        conv_ids = [m.conversation_id for m in memberships]
        if not conv_ids:
            return []

        member_map = {m.conversation_id: m for m in memberships}
        convs = (
            self.db.query(Conversation)
            .filter(Conversation.id.in_(conv_ids))
            .order_by(Conversation.updated_at.desc())
            .all()
        )

        peer_ids = [
            self.peer_user_id(c, user_id)
            for c in convs
            if c.type == "direct"
        ]
        user_ids = set(peer_ids)
        if any(c.type == "saved" for c in convs):
            user_ids.add(user_id)
        users = (
            {
                u.id: u
                for u in self.db.query(User).filter(User.id.in_(user_ids)).all()
            }
            if user_ids
            else {}
        )

        group_ids = [c.id for c in convs if c.type == "group"]
        member_count_map: Dict[int, int] = {}
        members_preview_map: Dict[int, List[User]] = {}
        if group_ids:
            member_rows = (
                self.db.query(ConversationMember)
                .filter(ConversationMember.conversation_id.in_(group_ids))
                .order_by(ConversationMember.joined_at.asc())
                .all()
            )
            grouped: Dict[int, List[int]] = {}
            for row in member_rows:
                grouped.setdefault(row.conversation_id, []).append(row.user_id)
                member_count_map[row.conversation_id] = (
                    member_count_map.get(row.conversation_id, 0) + 1
                )
            preview_user_ids = {
                uid
                for ids in grouped.values()
                for uid in ids[:4]
            }
            preview_users = (
                {
                    u.id: u
                    for u in self.db.query(User)
                    .filter(User.id.in_(preview_user_ids))
                    .all()
                }
                if preview_user_ids
                else {}
            )
            for conv_id, ids in grouped.items():
                members_preview_map[conv_id] = [
                    preview_users[i] for i in ids[:4] if i in preview_users
                ]

        hidden_subq = (
            self.db.query(MessageHide.message_id)
            .filter(MessageHide.user_id == user_id)
            .subquery()
        )
        last_msg_subq = (
            self.db.query(
                Message.conversation_id.label("conversation_id"),
                func.max(Message.id).label("max_id"),
            )
            .filter(
                Message.conversation_id.in_(conv_ids),
                Message.deleted_at.is_(None),
                ~Message.id.in_(hidden_subq),
            )
            .group_by(Message.conversation_id)
            .subquery()
        )
        last_messages = {
            m.conversation_id: m
            for m in self.db.query(Message)
            .join(
                last_msg_subq,
                and_(
                    Message.conversation_id == last_msg_subq.c.conversation_id,
                    Message.id == last_msg_subq.c.max_id,
                ),
            )
            .all()
        }

        unread_rows = (
            self.db.query(
                Message.conversation_id,
                func.count(Message.id).label("cnt"),
            )
            .join(
                ConversationMember,
                and_(
                    ConversationMember.conversation_id == Message.conversation_id,
                    ConversationMember.user_id == user_id,
                    ConversationMember.archived_at.is_(None),
                ),
            )
            .filter(
                Message.conversation_id.in_(conv_ids),
                Message.sender_id != user_id,
                Message.deleted_at.is_(None),
                ~Message.id.in_(hidden_subq),
                or_(
                    ConversationMember.history_cleared_before_id.is_(None),
                    Message.id > ConversationMember.history_cleared_before_id,
                ),
                or_(
                    ConversationMember.last_read_message_id.is_(None),
                    Message.id > ConversationMember.last_read_message_id,
                ),
            )
            .group_by(Message.conversation_id)
            .all()
        )
        unread_map = {row.conversation_id: row.cnt for row in unread_rows}

        me = self.db.query(User).filter(User.id == user_id).first()
        mention_map: Dict[int, int] = {}
        if me is not None and group_ids:
            unread_group_ids = [
                gid for gid in group_ids if unread_map.get(gid, 0) > 0
            ]
            if unread_group_ids:
                admin_map = {
                    c.id: bool(
                        member_map[c.id].is_admin
                        or c.created_by_user_id == user_id
                    )
                    for c in convs
                    if c.type == "group" and c.id in member_map
                }
                unread_msgs = (
                    self.db.query(Message)
                    .join(
                        ConversationMember,
                        and_(
                            ConversationMember.conversation_id
                            == Message.conversation_id,
                            ConversationMember.user_id == user_id,
                        ),
                    )
                    .filter(
                        Message.conversation_id.in_(unread_group_ids),
                        Message.sender_id != user_id,
                        Message.deleted_at.is_(None),
                        ~Message.id.in_(hidden_subq),
                        or_(
                            ConversationMember.history_cleared_before_id.is_(None),
                            Message.id
                            > ConversationMember.history_cleared_before_id,
                        ),
                        or_(
                            ConversationMember.last_read_message_id.is_(None),
                            Message.id > ConversationMember.last_read_message_id,
                        ),
                    )
                    .all()
                )
                for msg in unread_msgs:
                    if self._content_mentions_user(
                        msg.content or "",
                        me,
                        is_admin=admin_map.get(msg.conversation_id, False),
                    ):
                        mention_map[msg.conversation_id] = (
                            mention_map.get(msg.conversation_id, 0) + 1
                        )

        reaction_rows = (
            self.db.query(
                Message.conversation_id,
                func.count(MessageReaction.id).label("cnt"),
            )
            .join(Message, Message.id == MessageReaction.message_id)
            .join(
                ConversationMember,
                and_(
                    ConversationMember.conversation_id == Message.conversation_id,
                    ConversationMember.user_id == user_id,
                ),
            )
            .filter(
                Message.conversation_id.in_(conv_ids),
                Message.sender_id == user_id,
                Message.deleted_at.is_(None),
                MessageReaction.user_id != user_id,
                ~Message.id.in_(hidden_subq),
                or_(
                    ConversationMember.reactions_seen_at.is_(None),
                    MessageReaction.created_at
                    > ConversationMember.reactions_seen_at,
                ),
            )
            .group_by(Message.conversation_id)
            .all()
        )
        reaction_map = {row.conversation_id: int(row.cnt) for row in reaction_rows}

        from app.services.chat_tag_service import tag_ids_by_conversation

        tag_map = tag_ids_by_conversation(self.db, user_id, conv_ids)

        results = []
        for conv in convs:
            member = member_map[conv.id]
            is_archived = member.archived_at is not None
            if archived_only and not is_archived:
                continue
            if not archived_only and is_archived:
                continue
            last_msg = last_messages.get(conv.id)
            cleared_before = int(getattr(member, "history_cleared_before_id", 0) or 0)
            if last_msg is not None and cleared_before and last_msg.id <= cleared_before:
                last_msg = (
                    self.db.query(Message)
                    .filter(
                        Message.conversation_id == conv.id,
                        Message.deleted_at.is_(None),
                        ~Message.id.in_(hidden_subq),
                        Message.id > cleared_before,
                    )
                    .order_by(Message.id.desc())
                    .first()
                )
            unread = unread_map.get(conv.id, 0)
            is_muted = self._expire_mute_if_needed(member)

            peer = None
            member_count = 0
            members_preview: List[User] = []
            if conv.type == "group":
                member_count = member_count_map.get(conv.id, 0)
                members_preview = members_preview_map.get(conv.id, [])
            elif conv.type == "saved":
                peer = users.get(user_id)
                member_count = 1
            else:
                peer_id = self.peer_user_id(conv, user_id)
                peer = users.get(peer_id)
                member_count = 2 if peer else 0
            results.append(
                {
                    "conversation": conv,
                    "peer": peer,
                    "last_message": last_msg,
                    "unread_count": unread,
                    "unread_mentions_count": mention_map.get(conv.id, 0),
                    "unread_reactions_count": reaction_map.get(conv.id, 0),
                    "pinned": member.pinned,
                    "archived": is_archived,
                    "muted": is_muted,
                    "muted_until": getattr(member, "muted_until", None)
                    if is_muted
                    else None,
                    "notify_mode": (
                        getattr(member, "notify_mode", None)
                        or ("mentions" if is_muted else "all")
                    ),
                    "wallpaper_style": (
                        (getattr(member, "wallpaper_style", None) or "").strip()
                        or None
                    ),
                    "wallpaper_url": (
                        (getattr(member, "wallpaper_url", None) or "").strip()
                        or None
                    ),
                    "bubble_accent": (
                        (getattr(member, "bubble_accent", None) or "").strip()
                        or None
                    ),
                    "member_count": member_count,
                    "members_preview": members_preview,
                    "tag_ids": tag_map.get(conv.id, []),
                }
            )

        results.sort(
            key=lambda r: (
                r["conversation"].type != "saved",
                not r.get("pinned", False),
                -(r["conversation"].updated_at or r["conversation"].created_at).timestamp()
                if r["conversation"].updated_at or r["conversation"].created_at
                else 0,
            )
        )
        return results

    def get_conversation_row(self, conversation_id: int, user_id: int) -> Optional[dict]:
        if not self._is_member(conversation_id, user_id):
            return None
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        if not conv:
            return None
        member = (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == user_id,
            )
            .first()
        )
        if not member:
            return None
        cleared_before = int(getattr(member, "history_cleared_before_id", 0) or 0)
        hidden_subq = (
            self.db.query(MessageHide.message_id)
            .filter(MessageHide.user_id == user_id)
            .subquery()
        )
        last_msg_q = self.db.query(Message).filter(
            Message.conversation_id == conv.id,
            Message.deleted_at.is_(None),
            ~Message.id.in_(hidden_subq),
        )
        if cleared_before:
            last_msg_q = last_msg_q.filter(Message.id > cleared_before)
        last_msg = last_msg_q.order_by(Message.id.desc()).first()
        unread_q = self.db.query(func.count(Message.id)).filter(
            Message.conversation_id == conv.id,
            Message.sender_id != user_id,
            Message.deleted_at.is_(None),
            ~Message.id.in_(hidden_subq),
        )
        if cleared_before:
            unread_q = unread_q.filter(Message.id > cleared_before)
        if member.last_read_message_id:
            unread_q = unread_q.filter(Message.id > member.last_read_message_id)
        unread = unread_q.scalar() or 0
        unread_mentions = 0
        if conv.type == "group" and unread > 0:
            me = self.db.query(User).filter(User.id == user_id).first()
            if me is not None:
                is_admin = bool(
                    member.is_admin or conv.created_by_user_id == user_id
                )
                mention_q = self.db.query(Message).filter(
                    Message.conversation_id == conv.id,
                    Message.sender_id != user_id,
                    Message.deleted_at.is_(None),
                    ~Message.id.in_(hidden_subq),
                )
                if cleared_before:
                    mention_q = mention_q.filter(Message.id > cleared_before)
                if member.last_read_message_id:
                    mention_q = mention_q.filter(
                        Message.id > member.last_read_message_id
                    )
                for msg in mention_q.all():
                    if self._content_mentions_user(
                        msg.content or "", me, is_admin=is_admin
                    ):
                        unread_mentions += 1
        reaction_q = (
            self.db.query(func.count(MessageReaction.id))
            .join(Message, Message.id == MessageReaction.message_id)
            .filter(
                Message.conversation_id == conv.id,
                Message.sender_id == user_id,
                Message.deleted_at.is_(None),
                MessageReaction.user_id != user_id,
                ~Message.id.in_(hidden_subq),
            )
        )
        seen_at = getattr(member, "reactions_seen_at", None)
        if seen_at is not None:
            reaction_q = reaction_q.filter(MessageReaction.created_at > seen_at)
        unread_reactions = int(reaction_q.scalar() or 0)
        peer = None
        member_count = 0
        members_preview: List[User] = []
        if conv.type == "group":
            member_count = self._member_count(conv.id)
            members_preview = self._members_preview(conv.id)
        elif conv.type == "saved":
            peer = self.db.query(User).filter(User.id == user_id).first()
            member_count = 1
        else:
            peer_id = self.peer_user_id(conv, user_id)
            peer = self.db.query(User).filter(User.id == peer_id).first()
            member_count = 2 if peer else 0
        is_muted = self._expire_mute_if_needed(member)
        from app.services.chat_tag_service import tag_ids_for_conversation

        return {
            "conversation": conv,
            "peer": peer,
            "last_message": last_msg,
            "unread_count": unread,
            "unread_mentions_count": unread_mentions,
            "unread_reactions_count": unread_reactions,
            "pinned": member.pinned,
            "archived": member.archived_at is not None,
            "muted": is_muted,
            "muted_until": getattr(member, "muted_until", None)
            if is_muted
            else None,
            "notify_mode": (
                getattr(member, "notify_mode", None)
                or ("mentions" if is_muted else "all")
            ),
            "wallpaper_style": (
                (getattr(member, "wallpaper_style", None) or "").strip() or None
            ),
            "wallpaper_url": (
                (getattr(member, "wallpaper_url", None) or "").strip() or None
            ),
            "bubble_accent": (
                (getattr(member, "bubble_accent", None) or "").strip() or None
            ),
            "member_count": member_count,
            "members_preview": members_preview,
            "tag_ids": tag_ids_for_conversation(self.db, user_id, conv.id),
        }

    _WALLPAPER_STYLES = frozenset(
        {"pattern", "solid", "dusk", "forest", "sand", "night"}
    )
    _FREE_WALLPAPER_STYLES = frozenset({"pattern", "solid"})
    _BUBBLE_ACCENTS = frozenset(
        {"default", "mint", "sky", "rose", "amber", "slate", "grape"}
    )
    _FREE_BUBBLE_ACCENTS = frozenset({"default"})

    def set_wallpaper_style(
        self,
        conversation_id: int,
        user_id: int,
        style: Optional[str] = None,
        *,
        wallpaper_url: Optional[str] = None,
        set_style: bool = True,
        set_url: bool = False,
        apply_to_all: bool = False,
    ):
        """Set built-in style and/or custom wallpaper URL for the member.

        Setting a style clears custom URL. Setting a URL keeps style as soft
        fallback. Returns (style, wallpaper_url) after update.
        """
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        if not set_style and not set_url:
            raise ValueError("bad_wallpaper_style")

        style_value: Optional[str] = None
        if set_style:
            cleaned = (style or "").strip().lower()
            if cleaned and cleaned not in self._WALLPAPER_STYLES:
                raise ValueError("bad_wallpaper_style")
            style_value = cleaned or None

        url_value: Optional[str] = None
        if set_url:
            cleaned_url = (wallpaper_url or "").strip()
            if cleaned_url:
                if len(cleaned_url) > 512:
                    raise ValueError("bad_wallpaper_url")
                lower = cleaned_url.lower()
                if not (
                    lower.startswith("http://")
                    or lower.startswith("https://")
                    or lower.startswith("/")
                ):
                    raise ValueError("bad_wallpaper_url")
                url_value = cleaned_url
            else:
                url_value = None

        needs_wallpaper = bool(set_url and url_value) or (
            bool(set_style)
            and bool(style_value)
            and style_value not in self._FREE_WALLPAPER_STYLES
        )
        if needs_wallpaper and not self._has_feature(user_id, "chat_wallpaper"):
            raise ValueError("wallpaper_premium_required")

        def _apply(member: ConversationMember) -> None:
            if set_url and not set_style:
                member.wallpaper_url = url_value
            elif set_style and not set_url:
                member.wallpaper_style = style_value
                member.wallpaper_url = None
            else:
                # Both provided: custom URL wins; style kept as soft fallback.
                if set_style:
                    member.wallpaper_style = style_value
                member.wallpaper_url = url_value

        if apply_to_all:
            members = (
                self.db.query(ConversationMember)
                .filter(ConversationMember.user_id == user_id)
                .all()
            )
            for m in members:
                _apply(m)
            # Return representative values after apply.
            if set_url and not set_style:
                style_out = None
                if members:
                    style_out = (
                        (getattr(members[0], "wallpaper_style", None) or "").strip()
                        or None
                    )
                return style_out, url_value
            return style_value, (url_value if set_url else None)

        member = (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == user_id,
            )
            .first()
        )
        if not member:
            raise ValueError("forbidden")
        _apply(member)
        return (
            (getattr(member, "wallpaper_style", None) or "").strip() or None,
            (getattr(member, "wallpaper_url", None) or "").strip() or None,
        )

    def set_bubble_accent(
        self,
        conversation_id: int,
        user_id: int,
        accent: Optional[str],
        *,
        apply_to_all: bool = False,
    ) -> Optional[str]:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        value: Optional[str] = None
        if accent is not None:
            cleaned = (accent or "").strip().lower()
            if cleaned in ("", "default"):
                value = None
            elif cleaned not in self._BUBBLE_ACCENTS:
                raise ValueError("bad_bubble_accent")
            else:
                value = cleaned
        if value is not None and value not in self._FREE_BUBBLE_ACCENTS:
            if not self._has_feature(user_id, "chat_wallpaper"):
                raise ValueError("bubble_premium_required")
        if apply_to_all:
            members = (
                self.db.query(ConversationMember)
                .filter(ConversationMember.user_id == user_id)
                .all()
            )
            for m in members:
                m.bubble_accent = value
            return value
        member = (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == user_id,
            )
            .first()
        )
        if not member:
            raise ValueError("forbidden")
        member.bubble_accent = value
        return value

    def set_pinned(self, conversation_id: int, user_id: int, pinned: bool) -> None:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        member = (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == user_id,
            )
            .first()
        )
        if not member:
            raise ValueError("forbidden")
        if pinned and not bool(member.pinned):
            count = (
                self.db.query(func.count(ConversationMember.id))
                .filter(
                    ConversationMember.user_id == user_id,
                    ConversationMember.pinned.is_(True),
                )
                .scalar()
            )
            if int(count or 0) >= self._pinned_chat_limit_for(user_id):
                raise ValueError("pinned_chat_limit")
        member.pinned = pinned

    def set_auto_translate(
        self, conversation_id: int, user_id: int, enabled: bool
    ) -> None:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        member = (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == user_id,
            )
            .first()
        )
        if not member:
            raise ValueError("forbidden")
        next_enabled = bool(enabled)
        if next_enabled and not self._has_feature(user_id, "auto_translate"):
            raise ValueError("auto_translate_required")
        member.auto_translate = next_enabled

    _NOTIFY_MODES = frozenset({"all", "mentions", "none"})

    @classmethod
    def _normalize_notify_mode(cls, value: Optional[str], *, muted: bool) -> str:
        mode = (value or "").strip().lower()
        if mode not in cls._NOTIFY_MODES:
            mode = "mentions" if muted else "all"
        if muted and mode == "all":
            # Mute always suppresses normal messages.
            mode = "mentions"
        if not muted:
            mode = "all"
        return mode

    def _expire_mute_if_needed(self, member: ConversationMember) -> bool:
        """Clear timed mute when muted_until has passed. Returns True if muted."""
        if member.muted_at is None:
            if getattr(member, "muted_until", None) is not None:
                member.muted_until = None
            if getattr(member, "notify_mode", "all") != "all":
                member.notify_mode = "all"
            return False
        until = getattr(member, "muted_until", None)
        if until is None:
            return True
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        until_naive = until if until.tzinfo is None else until.astimezone(
            timezone.utc
        ).replace(tzinfo=None)
        if until_naive <= now:
            member.muted_at = None
            member.muted_until = None
            member.notify_mode = "all"
            return False
        return True

    def set_muted(
        self,
        conversation_id: int,
        user_id: int,
        muted: bool,
        muted_until: Optional[datetime] = None,
        notify_mode: Optional[str] = None,
    ) -> tuple[Optional[datetime], str]:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        member = (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == user_id,
            )
            .first()
        )
        if not member:
            raise ValueError("forbidden")
        mode = self._normalize_notify_mode(notify_mode, muted=muted)
        if not muted:
            member.muted_at = None
            member.muted_until = None
            member.notify_mode = "all"
            return None, "all"
        member.muted_at = datetime.now(timezone.utc).replace(tzinfo=None)
        member.notify_mode = mode
        if muted_until is None:
            member.muted_until = None
            return None, mode
        if muted_until.tzinfo is None:
            until_naive = muted_until
        else:
            until_naive = muted_until.astimezone(timezone.utc).replace(
                tzinfo=None
            )
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        if until_naive <= now:
            raise ValueError("invalid_muted_until")
        member.muted_until = until_naive
        return until_naive, mode

    def _get_group_or_error(self, conversation_id: int) -> Conversation:
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        if not conv:
            raise ValueError("not_found")
        if conv.type != "group":
            raise ValueError("not_group")
        return conv

    def update_group_title(
        self, conversation_id: int, user_id: int, title: str
    ) -> Conversation:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        conv = self._get_group_or_error(conversation_id)
        if not self._can_change_group_info(conversation_id, user_id):
            raise ValueError("forbidden")
        clean = title.strip()
        if not clean:
            raise ValueError("empty_title")
        from app.services.emoji_pack_service import (
            EmojiPackService,
            editor_or_preview_tokens,
        )

        # Creator authored the title; another admin may resend it on Save.
        own = int(conv.created_by_user_id or 0) == int(user_id)
        clean = (
            editor_or_preview_tokens(
                EmojiPackService(self.db), user_id, clean, own=own
            )
            or clean
        )
        conv.title = clean[:120]
        conv.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        return conv

    def set_group_only_admins_can_post(
        self, conversation_id: int, actor_id: int, enabled: bool
    ) -> Conversation:
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        conv = self._get_group_or_error(conversation_id)
        if not self._can_manage_group_posting_permissions(conversation_id, actor_id):
            raise ValueError("forbidden")
        conv.only_admins_can_post = bool(enabled)
        conv.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        return conv

    def set_group_is_forum(
        self, conversation_id: int, actor_id: int, enabled: bool
    ) -> Conversation:
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        conv = self._get_group_or_error(conversation_id)
        if not self._can_change_group_info(conversation_id, actor_id):
            raise ValueError("forbidden")
        was = bool(getattr(conv, "is_forum", False))
        conv.is_forum = bool(enabled)
        conv.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        if conv.is_forum and not was:
            # Re-enable keeps existing topics/message topic_ids; ensure General.
            self.ensure_general_topic(conversation_id, actor_id)
        # Disable only flips the flag — topics stay dormant for a later re-enable.
        return conv

    def ensure_general_topic(
        self, conversation_id: int, actor_id: Optional[int] = None
    ) -> ForumTopic:
        existing = (
            self.db.query(ForumTopic)
            .filter(
                ForumTopic.conversation_id == conversation_id,
                ForumTopic.is_general.is_(True),
            )
            .first()
        )
        if existing:
            return existing
        topic = ForumTopic(
            conversation_id=conversation_id,
            title="General",
            icon_emoji="💬",
            created_by_user_id=actor_id,
            is_general=True,
        )
        self.db.add(topic)
        self.db.flush()
        return topic

    def list_forum_topics(
        self,
        conversation_id: int,
        user_id: int,
        *,
        include_closed: bool = False,
    ) -> List[ForumTopic]:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        conv = self._get_group_or_error(conversation_id)
        if not bool(getattr(conv, "is_forum", False)):
            return []
        self.ensure_general_topic(conversation_id, user_id)
        show_closed = bool(include_closed) and self._can_change_group_info(
            conversation_id, user_id
        )
        q = self.db.query(ForumTopic).filter(
            ForumTopic.conversation_id == conversation_id
        )
        if not show_closed:
            q = q.filter(ForumTopic.closed_at.is_(None))
        return q.order_by(
            ForumTopic.is_general.desc(),
            ForumTopic.closed_at.is_(None).desc(),
            ForumTopic.created_at.asc(),
        ).all()

    def create_forum_topic(
        self,
        conversation_id: int,
        actor_id: int,
        title: str,
        icon_emoji: Optional[str] = None,
    ) -> ForumTopic:
        clean = (title or "").strip()[:128]
        if not clean:
            raise ValueError("empty_title")
        from app.services.emoji_pack_service import EmojiPackService

        EmojiPackService(self.db).require_send_tokens(actor_id, clean)
        EmojiPackService(self.db).require_send_tokens(actor_id, icon_emoji)
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        conv = self._get_group_or_error(conversation_id)
        if not bool(getattr(conv, "is_forum", False)):
            raise ValueError("not_a_forum")
        if not self._can_change_group_info(conversation_id, actor_id):
            raise ValueError("forbidden")
        self.ensure_general_topic(conversation_id, actor_id)
        emoji = (icon_emoji or "").strip()[:32] or None
        topic = ForumTopic(
            conversation_id=conversation_id,
            title=clean,
            icon_emoji=emoji,
            created_by_user_id=actor_id,
            is_general=False,
        )
        self.db.add(topic)
        self.db.flush()
        return topic

    def update_forum_topic(
        self,
        conversation_id: int,
        actor_id: int,
        topic_id: int,
        *,
        title: Optional[str] = None,
        closed: Optional[bool] = None,
        icon_emoji: Optional[str] = None,
    ) -> ForumTopic:
        from app.services.emoji_pack_service import EmojiPackService

        if title is not None:
            EmojiPackService(self.db).require_send_tokens(actor_id, title)
        if icon_emoji is not None:
            EmojiPackService(self.db).require_send_tokens(actor_id, icon_emoji)
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        if not self._can_change_group_info(conversation_id, actor_id):
            raise ValueError("forbidden")
        topic = (
            self.db.query(ForumTopic)
            .filter(
                ForumTopic.id == topic_id,
                ForumTopic.conversation_id == conversation_id,
            )
            .first()
        )
        if topic is None:
            raise ValueError("topic_not_found")
        if title is not None:
            clean = title.strip()[:128]
            if not clean:
                raise ValueError("empty_title")
            if topic.is_general and clean.lower() not in ("general", "общий"):
                # Allow rename of General but keep is_general.
                pass
            topic.title = clean
        if icon_emoji is not None:
            topic.icon_emoji = icon_emoji.strip()[:32] or None
        if closed is not None:
            if topic.is_general and closed:
                raise ValueError("cannot_close_general")
            topic.closed_at = (
                datetime.now(timezone.utc).replace(tzinfo=None) if closed else None
            )
        topic.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        self.db.flush()
        return topic

    def _resolve_topic_for_send(
        self, conversation_id: int, topic_id: Optional[int]
    ) -> Optional[int]:
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        if conv is None or conv.type != "group" or not bool(
            getattr(conv, "is_forum", False)
        ):
            return None
        general = self.ensure_general_topic(conversation_id)
        resolved = int(topic_id) if topic_id is not None else int(general.id)
        topic = (
            self.db.query(ForumTopic)
            .filter(
                ForumTopic.id == resolved,
                ForumTopic.conversation_id == conversation_id,
            )
            .first()
        )
        if topic is None:
            raise ValueError("topic_not_found")
        if topic.closed_at is not None:
            raise ValueError("topic_closed")
        return int(topic.id)

    def set_group_join_by_request_enabled(
        self, conversation_id: int, actor_id: int, enabled: bool
    ) -> Conversation:
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        conv = self._get_group_or_error(conversation_id)
        if not self._can_manage_group_members(conversation_id, actor_id):
            raise ValueError("forbidden")
        conv.join_by_request_enabled = bool(enabled)
        conv.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        return conv

    def set_group_slow_mode_seconds(
        self, conversation_id: int, actor_id: int, slow_mode_seconds: int
    ) -> Conversation:
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        conv = self._get_group_or_error(conversation_id)
        if not self._can_manage_group_posting_permissions(conversation_id, actor_id):
            raise ValueError("forbidden")
        value = max(0, min(int(slow_mode_seconds), 3600))
        conv.slow_mode_seconds = value
        conv.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        return conv

    def set_group_anti_flood_limit(
        self,
        conversation_id: int,
        actor_id: int,
        max_messages_per_minute: int,
    ) -> Conversation:
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        conv = self._get_group_or_error(conversation_id)
        if not self._can_manage_group_posting_permissions(conversation_id, actor_id):
            raise ValueError("forbidden")
        value = max(0, min(int(max_messages_per_minute), 120))
        conv.anti_flood_max_messages_per_minute = value
        conv.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        return conv

    def set_group_protect_content(
        self, conversation_id: int, actor_id: int, enabled: bool
    ) -> Conversation:
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        conv = self._get_group_or_error(conversation_id)
        if not self._can_manage_group_posting_permissions(conversation_id, actor_id):
            raise ValueError("forbidden")
        if bool(enabled) and not self._has_feature(actor_id, "no_forwards"):
            raise ValueError("no_forwards_required")
        conv.protect_content = bool(enabled)
        conv.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        return conv

    def set_auto_delete_seconds(
        self, conversation_id: int, actor_id: int, seconds: int
    ) -> Conversation:
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        if not conv:
            raise ValueError("not_found")
        if conv.type == "group":
            if not self._can_manage_group_posting_permissions(
                conversation_id, actor_id
            ):
                raise ValueError("forbidden")
        elif conv.type not in ("direct", "saved"):
            raise ValueError("forbidden")
        # Cap at 30 days; 0 disables.
        value = max(0, min(int(seconds), 30 * 24 * 3600))
        conv.auto_delete_seconds = value
        conv.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        return conv

    def purge_auto_deleted_messages(self, conversation_id: int) -> List[int]:
        """Soft-delete messages older than conversation auto-delete TTL."""
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        if not conv:
            return []
        ttl = int(getattr(conv, "auto_delete_seconds", 0) or 0)
        if ttl <= 0:
            return []
        cutoff = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(
            seconds=ttl
        )
        rows = (
            self.db.query(Message)
            .filter(
                Message.conversation_id == conversation_id,
                Message.deleted_at.is_(None),
                Message.created_at < cutoff,
            )
            .limit(200)
            .all()
        )
        if not rows:
            return []
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        ids = [m.id for m in rows]
        for msg in rows:
            msg.deleted_at = now
        (
            self.db.query(ConversationPinnedMessage)
            .filter(ConversationPinnedMessage.message_id.in_(ids))
            .delete(synchronize_session=False)
        )
        self._sync_legacy_pinned_slot(conv)
        return ids

    def set_group_avatar(
        self, conversation_id: int, actor_id: int, avatar_url: Optional[str]
    ) -> Conversation:
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        conv = self._get_group_or_error(conversation_id)
        if not self._can_change_group_info(conversation_id, actor_id):
            raise ValueError("forbidden")
        url = (avatar_url or "").strip()
        conv.avatar_url = url or None
        conv.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        return conv

    def add_group_members(
        self, conversation_id: int, actor_id: int, user_ids: List[int]
    ) -> int:
        if not self._can_invite_group_users(conversation_id, actor_id):
            raise ValueError("forbidden")
        conv = self._get_group_or_error(conversation_id)
        added = 0
        for uid in user_ids:
            if uid == actor_id:
                continue
            if self._is_member(conversation_id, uid):
                continue
            if self._is_group_member_banned(conversation_id, uid):
                raise ValueError("group_member_banned")
            target = self._get_user_or_404(uid)
            if self.has_block_between(actor_id, uid):
                raise ValueError("user_blocked")
            from app.services.group_add_privacy import can_add_user_to_group

            if not can_add_user_to_group(self.db, actor_id, target):
                raise ValueError("group_add_privacy_denied")
            from app.services.paid_features_service import PaidFeaturesService

            PaidFeaturesService(self.db).assert_can_join_paid_group(uid, conv)
            self.db.add(
                ConversationMember(conversation_id=conversation_id, user_id=uid)
            )
            added += 1
        return added

    def get_or_create_group_invite_token(
        self, conversation_id: int, actor_id: int, *, rotate: bool = False
    ) -> str:
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        conv = self._get_group_or_error(conversation_id)
        if not self._can_invite_group_users(conversation_id, actor_id):
            raise ValueError("forbidden")
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        self._cleanup_expired_invite_links(conversation_id)
        if rotate:
            (
                self.db.query(GroupInviteLink)
                .filter(
                    GroupInviteLink.conversation_id == conversation_id,
                    GroupInviteLink.revoked_at.is_(None),
                )
                .update({"revoked_at": now}, synchronize_session=False)
            )
        current = (
            self.db.query(GroupInviteLink)
            .filter(
                GroupInviteLink.conversation_id == conversation_id,
                GroupInviteLink.revoked_at.is_(None),
            )
            .order_by(GroupInviteLink.id.asc())
            .first()
        )
        if current is None:
            current = GroupInviteLink(
                conversation_id=conversation_id,
                token=self._generate_unique_group_invite_token(),
                created_by_user_id=actor_id,
            )
            self.db.add(current)
            self.db.flush()
        conv.invite_token = current.token
        conv.invite_token_updated_at = now
        conv.updated_at = now
        return current.token

    def create_group_invite_link(
        self,
        conversation_id: int,
        actor_id: int,
        *,
        expires_at: Optional[datetime] = None,
        max_uses: Optional[int] = None,
    ) -> GroupInviteLink:
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        conv = self._get_group_or_error(conversation_id)
        if not self._can_invite_group_users(conversation_id, actor_id):
            raise ValueError("forbidden")
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        expires_naive = None
        if expires_at is not None:
            expires_naive = (
                expires_at
                if expires_at.tzinfo is None
                else expires_at.astimezone(timezone.utc).replace(tzinfo=None)
            )
            if expires_naive <= now:
                raise ValueError("invalid_invite_expiry")
        if max_uses is not None and max_uses <= 0:
            raise ValueError("invalid_invite_max_uses")
        row = GroupInviteLink(
            conversation_id=conversation_id,
            token=self._generate_unique_group_invite_token(),
            created_by_user_id=actor_id,
            expires_at=expires_naive,
            max_uses=max_uses,
            uses_count=0,
        )
        self.db.add(row)
        conv.updated_at = now
        conv.invite_token = row.token
        conv.invite_token_updated_at = now
        self.db.flush()
        return row

    def list_group_invite_links(
        self,
        conversation_id: int,
        actor_id: int,
        *,
        include_revoked: bool = True,
        limit: int = 200,
    ) -> List[GroupInviteLink]:
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        if not self._can_invite_group_users(conversation_id, actor_id):
            raise ValueError("forbidden")
        self._get_group_or_error(conversation_id)
        self._cleanup_expired_invite_links(conversation_id)
        q = self.db.query(GroupInviteLink).filter(
            GroupInviteLink.conversation_id == conversation_id
        )
        if not include_revoked:
            q = q.filter(GroupInviteLink.revoked_at.is_(None))
        return (
            q.order_by(GroupInviteLink.id.desc())
            .limit(limit)
            .all()
        )

    def revoke_group_invite_link(
        self,
        conversation_id: int,
        actor_id: int,
        invite_link_id: int,
    ) -> GroupInviteLink:
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        conv = self._get_group_or_error(conversation_id)
        if not self._can_invite_group_users(conversation_id, actor_id):
            raise ValueError("forbidden")
        row = (
            self.db.query(GroupInviteLink)
            .filter(
                GroupInviteLink.id == invite_link_id,
                GroupInviteLink.conversation_id == conversation_id,
            )
            .first()
        )
        if not row:
            raise ValueError("not_found")
        if row.revoked_at is None:
            row.revoked_at = datetime.now(timezone.utc).replace(tzinfo=None)
            conv.updated_at = row.revoked_at
        return row

    def join_group_by_invite_token(
        self, invite_token: str, user_id: int
    ) -> dict:
        token = (invite_token or "").strip()
        if not token:
            raise ValueError("invalid_invite")
        self._get_user_or_404(user_id)
        invite = (
            self.db.query(GroupInviteLink)
            .join(
                Conversation,
                Conversation.id == GroupInviteLink.conversation_id,
            )
            .filter(
                GroupInviteLink.token == token,
                Conversation.type == "group",
            )
            .first()
        )
        if not invite:
            raise ValueError("invalid_invite")
        conv = self._get_group_or_error(invite.conversation_id)
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        if invite.revoked_at is not None:
            raise ValueError("invalid_invite")
        if invite.expires_at is not None and invite.expires_at <= now:
            invite.revoked_at = now
            raise ValueError("invalid_invite")
        if invite.max_uses is not None and invite.uses_count >= invite.max_uses:
            invite.revoked_at = now
            raise ValueError("invalid_invite")
        if self._is_group_member_banned(conv.id, user_id):
            raise ValueError("group_member_banned")
        if self._is_member(conv.id, user_id):
            return {"status": "joined", "conversation": conv}
        from app.services.paid_features_service import PaidFeaturesService

        PaidFeaturesService(self.db).assert_can_join_paid_group(user_id, conv)
        if conv.join_by_request_enabled:
            request = (
                self.db.query(GroupJoinRequest)
                .filter(
                    GroupJoinRequest.conversation_id == conv.id,
                    GroupJoinRequest.user_id == user_id,
                )
                .first()
            )
            now = datetime.now(timezone.utc).replace(tzinfo=None)
            if request:
                request.status = "pending"
                request.requested_at = now
                request.reviewed_at = None
                request.reviewed_by_user_id = None
            else:
                self.db.add(
                    GroupJoinRequest(
                        conversation_id=conv.id,
                        user_id=user_id,
                        status="pending",
                    )
                )
            conv.updated_at = now
            invite.uses_count += 1
            self.db.flush()
            return {"status": "requested", "conversation": conv}
        self.db.add(
            ConversationMember(
                conversation_id=conv.id,
                user_id=user_id,
            )
        )
        conv.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        invite.uses_count += 1
        self.db.flush()
        return {"status": "joined", "conversation": conv}

    def list_group_join_requests(
        self,
        conversation_id: int,
        actor_id: int,
        *,
        status_filter: str = "pending",
        limit: int = 200,
    ) -> List[dict]:
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        if not self._can_manage_group_members(conversation_id, actor_id):
            raise ValueError("forbidden")
        self._get_group_or_error(conversation_id)
        q = self.db.query(GroupJoinRequest).filter(
            GroupJoinRequest.conversation_id == conversation_id
        )
        if status_filter:
            q = q.filter(GroupJoinRequest.status == status_filter)
        rows = (
            q.order_by(GroupJoinRequest.requested_at.desc())
            .limit(limit)
            .all()
        )
        if not rows:
            return []
        users = self.db.query(User).filter(
            User.id.in_([r.user_id for r in rows])
        ).all()
        by_id = {u.id: u for u in users}
        out: List[dict] = []
        for row in rows:
            user = by_id.get(row.user_id)
            if not user:
                continue
            out.append(
                {
                    "id": row.id,
                    "user": user,
                    "status": row.status,
                    "requested_at": row.requested_at,
                }
            )
        return out

    def list_join_requests_inbox(
        self, actor_id: int, *, limit: int = 200
    ) -> List[dict]:
        managed_rows = (
            self.db.query(Conversation.id)
            .join(
                ConversationMember,
                and_(
                    ConversationMember.conversation_id == Conversation.id,
                    ConversationMember.user_id == actor_id,
                ),
            )
            .filter(
                Conversation.type == "group",
                or_(
                    Conversation.created_by_user_id == actor_id,
                    and_(
                        ConversationMember.is_admin == True,  # noqa: E712
                        ConversationMember.can_manage_members == True,  # noqa: E712
                    ),
                ),
            )
            .all()
        )
        managed_conv_ids = [cid for (cid,) in managed_rows]
        if not managed_conv_ids:
            return []
        rows = (
            self.db.query(GroupJoinRequest)
            .filter(
                GroupJoinRequest.conversation_id.in_(managed_conv_ids),
                GroupJoinRequest.status == "pending",
            )
            .order_by(GroupJoinRequest.requested_at.desc())
            .limit(limit)
            .all()
        )
        if not rows:
            return []
        user_ids = {r.user_id for r in rows}
        users = (
            {
                u.id: u
                for u in self.db.query(User).filter(User.id.in_(user_ids)).all()
            }
            if user_ids
            else {}
        )
        out: List[dict] = []
        for row in rows:
            user = users.get(row.user_id)
            if not user:
                continue
            out.append(
                {
                    "id": row.id,
                    "conversation_id": row.conversation_id,
                    "user": user,
                    "status": row.status,
                    "requested_at": row.requested_at,
                }
            )
        return out

    def review_group_join_request(
        self,
        conversation_id: int,
        actor_id: int,
        request_id: int,
        *,
        approve: bool,
    ) -> GroupJoinRequest:
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        if not self._can_manage_group_members(conversation_id, actor_id):
            raise ValueError("forbidden")
        conv = self._get_group_or_error(conversation_id)
        row = (
            self.db.query(GroupJoinRequest)
            .filter(
                GroupJoinRequest.id == request_id,
                GroupJoinRequest.conversation_id == conversation_id,
            )
            .first()
        )
        if not row:
            raise ValueError("not_found")
        if row.status != "pending":
            raise ValueError("already_reviewed")
        if self._is_group_member_banned(conversation_id, row.user_id):
            raise ValueError("group_member_banned")

        now = datetime.now(timezone.utc).replace(tzinfo=None)
        if approve:
            from app.services.paid_features_service import PaidFeaturesService

            PaidFeaturesService(self.db).assert_can_join_paid_group(
                row.user_id, conv
            )
            if not self._is_member(conversation_id, row.user_id):
                self.db.add(
                    ConversationMember(
                        conversation_id=conversation_id,
                        user_id=row.user_id,
                    )
                )
            row.status = "approved"
        else:
            row.status = "rejected"
        row.reviewed_at = now
        row.reviewed_by_user_id = actor_id
        conv.updated_at = now
        self.db.flush()
        return row

    def create_group_system_note(
        self, conversation_id: int, actor_id: int, text: str
    ) -> Message:
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        conv = self._get_group_or_error(conversation_id)
        from app.services.emoji_pack_service import text_for_external

        body = text_for_external(text)
        if not body:
            raise ValueError("empty_message")
        note = Message(
            conversation_id=conversation_id,
            sender_id=actor_id,
            type="text",
            content=body[:4000],
        )
        self.db.add(note)
        conv.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        self.db.flush()
        return note

    def list_group_moderation_log(
        self,
        conversation_id: int,
        actor_id: int,
        *,
        action_filter: str = "all",
        limit: int = 200,
    ) -> List[Message]:
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        if not self._can_manage_group_members(conversation_id, actor_id):
            raise ValueError("forbidden")
        self._get_group_or_error(conversation_id)
        q = self.db.query(Message).filter(
            Message.conversation_id == conversation_id,
            Message.deleted_at.is_(None),
            Message.content.like("🛡 %"),
        )
        if action_filter == "settings":
            q = q.filter(
                or_(
                    Message.content.ilike("%changed group title%"),
                    Message.content.ilike("%Sending mode changed%"),
                    Message.content.ilike("%Join mode changed%"),
                )
            )
        elif action_filter == "roles":
            q = q.filter(
                or_(
                    Message.content.ilike("%moderator role%"),
                    Message.content.ilike("%moderator permissions%"),
                )
            )
        elif action_filter == "restrictions":
            q = q.filter(
                or_(
                    Message.content.ilike("%restricted messaging%"),
                    Message.content.ilike("%removed messaging restriction%"),
                )
            )
        elif action_filter == "bans":
            q = q.filter(
                or_(
                    Message.content.ilike("% banned %"),
                    Message.content.ilike("% unbanned %"),
                )
            )
        elif action_filter == "joins":
            q = q.filter(Message.content.ilike("%join request%"))
        rows = (
            q.order_by(Message.id.desc())
            .limit(limit)
            .all()
        )
        rows.reverse()
        return rows

    def remove_group_member(
        self, conversation_id: int, actor_id: int, target_user_id: int
    ) -> None:
        if target_user_id == actor_id:
            if not self._is_member(conversation_id, actor_id):
                raise ValueError("forbidden")
        elif not self._can_manage_group_members(conversation_id, actor_id):
            raise ValueError("forbidden")
        conv = self._get_group_or_error(conversation_id)
        if (
            target_user_id != actor_id
            and conv.created_by_user_id == target_user_id
        ):
            raise ValueError("forbidden")
        member = (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == target_user_id,
            )
            .first()
        )
        if not member:
            raise ValueError("not_found")
        self.db.delete(member)
        self.db.flush()
        if self._member_count(conversation_id) == 0:
            self.db.delete(conv)

    def leave_group(self, conversation_id: int, user_id: int) -> None:
        self.remove_group_member(conversation_id, user_id, user_id)

    def set_group_member_admin(
        self,
        conversation_id: int,
        actor_id: int,
        target_user_id: int,
        is_admin: bool,
    ) -> ConversationMember:
        conv = self._get_group_or_error(conversation_id)
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        if conv.created_by_user_id != actor_id:
            raise ValueError("forbidden")
        if target_user_id == actor_id:
            raise ValueError("cannot_change_self_role")
        member = (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == target_user_id,
            )
            .first()
        )
        if not member:
            raise ValueError("not_found")
        member.is_admin = bool(is_admin)
        for attr in (
            "can_manage_members",
            "can_manage_posting_permissions",
            "can_change_info",
            "can_delete_messages",
            "can_pin_messages",
            "can_invite_users",
            "can_manage_video_chats",
        ):
            setattr(member, attr, bool(is_admin))
        conv.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        return member

    def set_group_member_permissions(
        self,
        conversation_id: int,
        actor_id: int,
        target_user_id: int,
        *,
        can_manage_members: bool,
        can_manage_posting_permissions: bool,
        can_change_info: bool = False,
        can_delete_messages: bool = False,
        can_pin_messages: bool = False,
        can_invite_users: bool = False,
        can_manage_video_chats: bool = False,
    ) -> ConversationMember:
        conv = self._get_group_or_error(conversation_id)
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        if conv.created_by_user_id != actor_id:
            raise ValueError("forbidden")
        if target_user_id == actor_id:
            raise ValueError("cannot_change_self_role")
        member = self._get_member_record(conversation_id, target_user_id)
        if not member:
            raise ValueError("not_found")
        if not member.is_admin:
            raise ValueError("target_not_admin")
        member.can_manage_members = bool(can_manage_members)
        member.can_manage_posting_permissions = bool(
            can_manage_posting_permissions
        )
        member.can_change_info = bool(can_change_info)
        member.can_delete_messages = bool(can_delete_messages)
        member.can_pin_messages = bool(can_pin_messages)
        member.can_invite_users = bool(can_invite_users)
        member.can_manage_video_chats = bool(can_manage_video_chats)
        conv.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        return member

    def set_group_member_send_restriction(
        self,
        conversation_id: int,
        actor_id: int,
        target_user_id: int,
        *,
        send_restricted: bool,
        send_restricted_until: Optional[datetime],
        reason: Optional[str],
    ) -> ConversationMember:
        if send_restricted:
            from app.services.emoji_pack_service import EmojiPackService

            EmojiPackService(self.db).require_send_tokens(actor_id, reason)
        conv = self._get_group_or_error(conversation_id)
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        if target_user_id == actor_id:
            raise ValueError("cannot_restrict_self")
        if not self._can_manage_group_members(conversation_id, actor_id):
            raise ValueError("forbidden")
        if conv.created_by_user_id == target_user_id:
            raise ValueError("cannot_restrict_creator")

        target_member = self._get_member_record(conversation_id, target_user_id)
        if not target_member:
            raise ValueError("not_found")
        if (
            target_member.is_admin
            and conv.created_by_user_id != actor_id
        ):
            raise ValueError("cannot_restrict_admin")

        now = datetime.now(timezone.utc).replace(tzinfo=None)
        if send_restricted:
            until_naive: Optional[datetime] = None
            if send_restricted_until is not None:
                if send_restricted_until.tzinfo is None:
                    until_naive = send_restricted_until
                else:
                    until_naive = send_restricted_until.astimezone(
                        timezone.utc
                    ).replace(tzinfo=None)
                if until_naive <= now:
                    raise ValueError("invalid_restriction_until")
            target_member.send_restricted = True
            target_member.send_restricted_until = until_naive
            target_member.send_restriction_reason = (reason or "").strip()[:240] or None
        else:
            target_member.send_restricted = False
            target_member.send_restricted_until = None
            target_member.send_restriction_reason = None

        conv.updated_at = now
        return target_member

    def ban_group_member(
        self,
        conversation_id: int,
        actor_id: int,
        target_user_id: int,
        *,
        reason: Optional[str],
        banned_until: Optional[datetime],
    ) -> GroupMemberBan:
        from app.services.emoji_pack_service import EmojiPackService

        EmojiPackService(self.db).require_send_tokens(actor_id, reason)
        conv = self._get_group_or_error(conversation_id)
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        if target_user_id == actor_id:
            raise ValueError("cannot_ban_self")
        if not self._can_manage_group_members(conversation_id, actor_id):
            raise ValueError("forbidden")
        if conv.created_by_user_id == target_user_id:
            raise ValueError("cannot_ban_creator")
        target_member = self._get_member_record(conversation_id, target_user_id)
        if (
            target_member is not None
            and target_member.is_admin
            and conv.created_by_user_id != actor_id
        ):
            raise ValueError("cannot_ban_admin")
        self._get_user_or_404(target_user_id)
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        until_naive: Optional[datetime] = None
        if banned_until is not None:
            if banned_until.tzinfo is None:
                until_naive = banned_until
            else:
                until_naive = banned_until.astimezone(timezone.utc).replace(tzinfo=None)
            if until_naive <= now:
                raise ValueError("invalid_ban_until")

        row = (
            self.db.query(GroupMemberBan)
            .filter(
                GroupMemberBan.conversation_id == conversation_id,
                GroupMemberBan.user_id == target_user_id,
            )
            .first()
        )
        if not row:
            row = GroupMemberBan(
                conversation_id=conversation_id,
                user_id=target_user_id,
            )
            self.db.add(row)
        row.banned = True
        row.banned_by_user_id = actor_id
        row.reason = (reason or "").strip()[:240] or None
        row.banned_until = until_naive

        if target_member is not None:
            self.db.delete(target_member)
            self.db.flush()

        conv.updated_at = now
        return row

    def unban_group_member(
        self, conversation_id: int, actor_id: int, target_user_id: int
    ) -> GroupMemberBan:
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        if not self._can_manage_group_members(conversation_id, actor_id):
            raise ValueError("forbidden")
        self._get_group_or_error(conversation_id)
        row = (
            self.db.query(GroupMemberBan)
            .filter(
                GroupMemberBan.conversation_id == conversation_id,
                GroupMemberBan.user_id == target_user_id,
                GroupMemberBan.banned == True,  # noqa: E712
            )
            .first()
        )
        if not row:
            raise ValueError("not_found")
        row.banned = False
        row.banned_until = None
        row.reason = None
        row.banned_by_user_id = actor_id
        return row

    def list_group_bans(
        self, conversation_id: int, user_id: int, limit: int = 200
    ) -> List[dict]:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        if not self._can_manage_group_members(conversation_id, user_id):
            raise ValueError("forbidden")
        self._cleanup_expired_group_bans(conversation_id)
        rows = (
            self.db.query(GroupMemberBan)
            .filter(
                GroupMemberBan.conversation_id == conversation_id,
                GroupMemberBan.banned == True,  # noqa: E712
            )
            .order_by(GroupMemberBan.created_at.desc())
            .limit(limit)
            .all()
        )
        if not rows:
            return []
        user_ids = [r.user_id for r in rows]
        users = self.db.query(User).filter(User.id.in_(user_ids)).all()
        by_id = {u.id: u for u in users}
        out: List[dict] = []
        for row in rows:
            user = by_id.get(row.user_id)
            if not user:
                continue
            out.append(
                {
                    "user": user,
                    "reason": row.reason,
                    "banned_until": row.banned_until,
                    "banned_at": row.updated_at or row.created_at,
                }
            )
        return out

    def block_user(self, blocker_id: int, blocked_id: int) -> None:
        if blocker_id == blocked_id:
            raise ValueError("self_block")
        self._get_user_or_404(blocked_id)
        existing = (
            self.db.query(UserBlock)
            .filter(
                UserBlock.blocker_user_id == blocker_id,
                UserBlock.blocked_user_id == blocked_id,
            )
            .first()
        )
        if existing:
            return
        self.db.add(
            UserBlock(blocker_user_id=blocker_id, blocked_user_id=blocked_id)
        )

    def unblock_user(self, blocker_id: int, blocked_id: int) -> bool:
        row = (
            self.db.query(UserBlock)
            .filter(
                UserBlock.blocker_user_id == blocker_id,
                UserBlock.blocked_user_id == blocked_id,
            )
            .first()
        )
        if not row:
            return False
        self.db.delete(row)
        return True

    def is_user_blocked_by_me(self, viewer_id: int, other_id: int) -> bool:
        return (
            self.db.query(UserBlock.id)
            .filter(
                UserBlock.blocker_user_id == viewer_id,
                UserBlock.blocked_user_id == other_id,
            )
            .first()
            is not None
        )

    def list_blocked_users(self, blocker_id: int) -> List[User]:
        rows = (
            self.db.query(User)
            .join(UserBlock, UserBlock.blocked_user_id == User.id)
            .filter(
                UserBlock.blocker_user_id == blocker_id,
                User.deleted_at.is_(None),
            )
            .order_by(UserBlock.id.desc())
            .limit(500)
            .all()
        )
        return rows

    def _history_cleared_before_id(
        self, conversation_id: int, user_id: int
    ) -> Optional[int]:
        member = self._get_member_record(conversation_id, user_id)
        if member is None:
            return None
        value = getattr(member, "history_cleared_before_id", None)
        return int(value) if value else None

    def clear_history(
        self,
        conversation_id: int,
        user_id: int,
        *,
        also_for_peer: bool = False,
    ) -> tuple[int, Optional[int]]:
        """Hide all current messages for this user (Telegram clear history).

        Returns (cleared_before_id, peer_user_id_if_also_cleared).
        `also_for_peer` applies the same cursor to the DM peer only.
        """
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        member = self._get_member_record(conversation_id, user_id)
        if member is None:
            raise ValueError("forbidden")
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        if not conv:
            raise ValueError("not_found")
        peer_cleared_id: Optional[int] = None
        if also_for_peer:
            if conv.type != "direct":
                raise ValueError("also_for_peer_direct_only")
            peer_id = self.peer_user_id(conv, user_id)
            peer_member = self._get_member_record(conversation_id, peer_id)
            if peer_member is None:
                raise ValueError("forbidden")
            peer_cleared_id = peer_id
        max_id = (
            self.db.query(func.max(Message.id))
            .filter(
                Message.conversation_id == conversation_id,
                Message.deleted_at.is_(None),
            )
            .scalar()
        )
        cleared_to = int(max_id or 0)
        member.history_cleared_before_id = cleared_to
        member.last_read_message_id = cleared_to or member.last_read_message_id
        if peer_cleared_id is not None:
            peer_member = self._get_member_record(
                conversation_id, peer_cleared_id
            )
            if peer_member is not None:
                peer_member.history_cleared_before_id = cleared_to
                peer_member.last_read_message_id = (
                    cleared_to or peer_member.last_read_message_id
                )
        return cleared_to, peer_cleared_id

    def list_common_groups(
        self, viewer_id: int, peer_id: int, *, limit: int = 50
    ) -> List[Conversation]:
        if viewer_id == peer_id:
            return []
        self._get_user_or_404(peer_id)
        viewer_groups = (
            self.db.query(ConversationMember.conversation_id)
            .join(Conversation, Conversation.id == ConversationMember.conversation_id)
            .filter(
                ConversationMember.user_id == viewer_id,
                Conversation.type == "group",
            )
            .subquery()
        )
        rows = (
            self.db.query(Conversation)
            .join(
                ConversationMember,
                ConversationMember.conversation_id == Conversation.id,
            )
            .filter(
                ConversationMember.user_id == peer_id,
                Conversation.id.in_(viewer_groups),
                Conversation.type == "group",
            )
            .order_by(Conversation.updated_at.desc(), Conversation.id.desc())
            .limit(max(1, min(int(limit), 100)))
            .all()
        )
        return rows

    def get_messages(
        self,
        conversation_id: int,
        user_id: int,
        cursor: Optional[int] = None,
        after_id: Optional[int] = None,
        limit: int = 50,
        topic_id: Optional[int] = None,
        tag_id: Optional[int] = None,
    ) -> Tuple[List[Message], bool]:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        # Best-effort TTL purge before serving history.
        try:
            self.purge_auto_deleted_messages(conversation_id)
        except Exception:
            pass

        hidden_ids = (
            self.db.query(MessageHide.message_id)
            .filter(MessageHide.user_id == user_id)
            .subquery()
        )
        cleared_before = self._history_cleared_before_id(conversation_id, user_id) or 0

        topic_filter = None
        if topic_id is not None:
            conv = (
                self.db.query(Conversation)
                .filter(Conversation.id == conversation_id)
                .first()
            )
            if conv is not None and bool(getattr(conv, "is_forum", False)):
                topic = (
                    self.db.query(ForumTopic)
                    .filter(
                        ForumTopic.id == topic_id,
                        ForumTopic.conversation_id == conversation_id,
                    )
                    .first()
                )
                if topic is None:
                    raise ValueError("topic_not_found")
                if topic.is_general:
                    topic_filter = or_(
                        Message.topic_id == topic.id,
                        Message.topic_id.is_(None),
                    )
                else:
                    topic_filter = Message.topic_id == topic.id

        if after_id is not None:
            q = self.db.query(Message).filter(
                Message.conversation_id == conversation_id,
                Message.deleted_at.is_(None),
                Message.id > after_id,
                Message.id > cleared_before,
                ~Message.id.in_(hidden_ids),
            )
            if topic_filter is not None:
                q = q.filter(topic_filter)
            if tag_id is not None:
                from app.models.saved_tag import SavedMessageTag

                q = q.join(
                    SavedMessageTag,
                    SavedMessageTag.message_id == Message.id,
                ).filter(SavedMessageTag.tag_id == int(tag_id))
            rows = q.order_by(Message.id.asc()).limit(limit + 1).all()
            has_more = len(rows) > limit
            if has_more:
                rows = rows[:limit]
            return rows, has_more

        q = (
            self.db.query(Message)
            .filter(
                Message.conversation_id == conversation_id,
                Message.deleted_at.is_(None),
                Message.id > cleared_before,
                ~Message.id.in_(hidden_ids),
            )
            .order_by(Message.id.desc())
        )
        if topic_filter is not None:
            q = q.filter(topic_filter)
        if tag_id is not None:
            from app.models.saved_tag import SavedMessageTag

            q = q.join(
                SavedMessageTag,
                SavedMessageTag.message_id == Message.id,
            ).filter(SavedMessageTag.tag_id == int(tag_id))
        if cursor:
            q = q.filter(Message.id < cursor)

        rows = q.limit(limit + 1).all()
        has_more = len(rows) > limit
        if has_more:
            rows = rows[:limit]
        rows.reverse()
        return rows, has_more

    def list_media_messages(
        self,
        conversation_id: int,
        user_id: int,
        *,
        kind: str = "all",
        cursor: Optional[int] = None,
        limit: int = 60,
        sender_id: Optional[int] = None,
    ) -> Tuple[List[Message], bool]:
        """Shared media / links for a chat (Telegram-style gallery source)."""
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")

        hidden_ids = (
            self.db.query(MessageHide.message_id)
            .filter(MessageHide.user_id == user_id)
            .subquery()
        )
        cleared_before = self._history_cleared_before_id(conversation_id, user_id) or 0

        q = (
            self.db.query(Message)
            .filter(
                Message.conversation_id == conversation_id,
                Message.deleted_at.is_(None),
                Message.id > cleared_before,
                ~Message.id.in_(hidden_ids),
            )
            .order_by(Message.id.desc())
        )
        if cursor:
            q = q.filter(Message.id < cursor)
        if sender_id is not None:
            q = q.filter(Message.sender_id == int(sender_id))

        kind_norm = (kind or "all").strip().lower()
        if kind_norm == "photos":
            q = q.filter(Message.type == "image", Message.media_url.isnot(None))
        elif kind_norm == "videos":
            q = q.filter(
                Message.type.in_(("video", "video_note")),
                Message.media_url.isnot(None),
            )
        elif kind_norm == "files":
            q = q.filter(Message.type == "file", Message.media_url.isnot(None))
        elif kind_norm == "links":
            q = q.filter(
                or_(
                    Message.content.ilike("%http://%"),
                    Message.content.ilike("%https://%"),
                )
            )
        elif kind_norm == "voices":
            q = q.filter(Message.type == "voice", Message.media_url.isnot(None))
        elif kind_norm == "stickers":
            q = q.filter(Message.type == "sticker", Message.media_url.isnot(None))
        else:
            q = q.filter(
                Message.type.in_(
                    ("image", "video", "video_note", "file", "voice", "sticker")
                ),
                Message.media_url.isnot(None),
            )

        rows = q.limit(limit + 1).all()
        has_more = len(rows) > limit
        if has_more:
            rows = rows[:limit]
        return rows, has_more

    def search_messages(
        self,
        user_id: int,
        query: str,
        *,
        conversation_id: Optional[int] = None,
        msg_type: Optional[str] = None,
        sender_id: Optional[int] = None,
        date_from: Optional[datetime] = None,
        date_to: Optional[datetime] = None,
        limit: int = 40,
    ) -> List[dict]:
        term = (query or "").strip()
        has_date = date_from is not None or date_to is not None
        if len(term) < 2 and not has_date:
            return []

        member_conv_ids = [
            cid
            for (cid,) in self.db.query(ConversationMember.conversation_id)
            .filter(ConversationMember.user_id == user_id)
            .all()
        ]
        if not member_conv_ids:
            return []

        if conversation_id is not None:
            if conversation_id not in member_conv_ids:
                raise ValueError("forbidden")
            conv_ids = [conversation_id]
        else:
            conv_ids = member_conv_ids

        hidden_subq = (
            self.db.query(MessageHide.message_id)
            .filter(MessageHide.user_id == user_id)
            .subquery()
        )
        filters = [
            Message.deleted_at.is_(None),
            Message.conversation_id.in_(conv_ids),
            ~Message.id.in_(hidden_subq),
        ]
        if len(term) >= 2:
            filters.append(
                or_(
                    Message.content.ilike(f"%{term}%"),
                    Message.media_url.ilike(f"%{term}%"),
                )
            )
        q = (
            self.db.query(Message)
            .filter(*filters)
            .order_by(Message.id.desc())
        )
        if msg_type:
            q = q.filter(Message.type == msg_type)
        if sender_id is not None:
            q = q.filter(Message.sender_id == int(sender_id))
        if date_from is not None:
            q = q.filter(Message.created_at >= date_from)
        if date_to is not None:
            q = q.filter(Message.created_at <= date_to)

        rows = q.limit(limit).all()
        if not rows:
            return []

        conv_rows = {
            cid: self.get_conversation_row(cid, user_id)
            for cid in {m.conversation_id for m in rows}
        }
        sender_ids = {m.sender_id for m in rows}
        users = (
            {
                u.id: u
                for u in self.db.query(User).filter(User.id.in_(sender_ids)).all()
            }
            if sender_ids
            else {}
        )

        hits: List[dict] = []
        lower_term = term.lower()
        for msg in rows:
            text = msg.content or ""
            if lower_term:
                idx = text.lower().find(lower_term)
            else:
                idx = -1
            if idx >= 0:
                start = max(0, idx - 40)
                end = min(len(text), idx + len(term) + 70)
                snippet = text[start:end].strip()
                if start > 0:
                    snippet = f"...{snippet}"
                if end < len(text):
                    snippet = f"{snippet}..."
            else:
                snippet = text[:120] if text else ""

            hits.append(
                {
                    "message": msg,
                    "conversation_row": conv_rows.get(msg.conversation_id),
                    "sender": users.get(msg.sender_id),
                    "snippet": snippet,
                }
            )
        return hits

    def _validate_message_payload(
        self,
        *,
        conversation_id: int,
        sender_id: int,
        msg_type: str,
        content: str,
        media_url: Optional[str] = None,
        reply_to_message_id: Optional[int] = None,
    ) -> Conversation:
        if not self._is_member(conversation_id, sender_id):
            raise ValueError("forbidden")

        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        if conv and conv.type == "direct":
            peer_id = self.peer_user_id(conv, sender_id)
            if self.has_block_between(sender_id, peer_id):
                raise ValueError("user_blocked")
        if (
            conv
            and conv.type == "group"
            and conv.only_admins_can_post
            and not self._is_group_admin(conversation_id, sender_id)
        ):
            raise ValueError("group_write_restricted")
        if conv and conv.type == "group":
            restricted, _, _ = self._is_member_send_restricted(conversation_id, sender_id)
            if restricted and not self._is_group_admin(conversation_id, sender_id):
                raise ValueError("group_user_restricted")
            if not self._is_group_admin(conversation_id, sender_id):
                member = self._get_member_record(conversation_id, sender_id)
                now = datetime.now(timezone.utc).replace(tzinfo=None)
                slow_mode_seconds = int(getattr(conv, "slow_mode_seconds", 0) or 0)
                if (
                    member is not None
                    and slow_mode_seconds > 0
                    and member.last_group_message_at is not None
                ):
                    elapsed = (now - member.last_group_message_at).total_seconds()
                    if elapsed < slow_mode_seconds:
                        raise ValueError("group_slow_mode")
                flood_limit = int(
                    getattr(conv, "anti_flood_max_messages_per_minute", 0) or 0
                )
                if flood_limit > 0:
                    recent_since = now - timedelta(minutes=1)
                    recent_count = (
                        self.db.query(func.count(Message.id))
                        .filter(
                            Message.conversation_id == conversation_id,
                            Message.sender_id == sender_id,
                            Message.deleted_at.is_(None),
                            Message.created_at >= recent_since,
                        )
                        .scalar()
                        or 0
                    )
                    if recent_count >= flood_limit:
                        raise ValueError("group_flood_limited")

        if msg_type == "text" and not content.strip():
            raise ValueError("empty_message")
        if msg_type == "image" and not media_url:
            raise ValueError("missing_media")
        if msg_type == "voice" and not media_url:
            raise ValueError("missing_media")
        if msg_type == "file" and not media_url:
            raise ValueError("missing_media")
        if msg_type == "video" and not media_url:
            raise ValueError("missing_media")
        if msg_type == "video_note" and not media_url:
            raise ValueError("missing_media")
        if msg_type == "sticker" and not media_url:
            raise ValueError("missing_media")
        if msg_type == "sticker" and media_url:
            from app.services.sticker_service import StickerService

            StickerService(self.db).require_sticker_send(sender_id, media_url)
        if msg_type == "poll" and not content.strip():
            raise ValueError("empty_poll")
        if msg_type == "location" and not content.strip():
            raise ValueError("empty_location")
        if msg_type == "story_reply":
            if not content.strip():
                raise ValueError("empty_story_reply")
            try:
                import json as _json

                data = _json.loads(content)
            except Exception as exc:
                raise ValueError("invalid_story_reply") from exc
            if not isinstance(data, dict):
                raise ValueError("invalid_story_reply")
            story_id = data.get("story_id")
            text = (data.get("text") or "").strip()
            if not isinstance(story_id, int) or story_id <= 0:
                raise ValueError("invalid_story_reply")
            if not text:
                raise ValueError("empty_story_reply")
            if len(text) > 1000:
                raise ValueError("story_reply_too_long")
        if reply_to_message_id is not None:
            reply_target = (
                self.db.query(Message.id)
                .filter(
                    Message.id == reply_to_message_id,
                    Message.conversation_id == conversation_id,
                    Message.deleted_at.is_(None),
                )
                .first()
            )
            if not reply_target:
                raise ValueError("invalid_reply")
        return conv

    def group_slow_mode_retry_after_seconds(
        self, conversation_id: int, sender_id: int
    ) -> int:
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        if not conv or conv.type != "group":
            return 0
        if self._is_group_admin(conversation_id, sender_id):
            return 0
        slow_mode_seconds = int(getattr(conv, "slow_mode_seconds", 0) or 0)
        if slow_mode_seconds <= 0:
            return 0
        member = self._get_member_record(conversation_id, sender_id)
        if not member or member.last_group_message_at is None:
            return 0
        elapsed = (
            datetime.now(timezone.utc).replace(tzinfo=None) - member.last_group_message_at
        ).total_seconds()
        remaining = int(slow_mode_seconds - elapsed + 0.999)
        return max(0, remaining)

    def group_flood_retry_after_seconds(self, conversation_id: int, sender_id: int) -> int:
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        if not conv or conv.type != "group":
            return 0
        if self._is_group_admin(conversation_id, sender_id):
            return 0
        flood_limit = int(getattr(conv, "anti_flood_max_messages_per_minute", 0) or 0)
        if flood_limit <= 0:
            return 0
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        recent_since = now - timedelta(minutes=1)
        oldest_recent = (
            self.db.query(Message.created_at)
            .filter(
                Message.conversation_id == conversation_id,
                Message.sender_id == sender_id,
                Message.deleted_at.is_(None),
                Message.created_at >= recent_since,
            )
            .order_by(Message.created_at.asc())
            .first()
        )
        if not oldest_recent or oldest_recent[0] is None:
            return 0
        elapsed = (now - oldest_recent[0]).total_seconds()
        remaining = int(60 - elapsed + 0.999)
        return max(0, remaining)

    @staticmethod
    def _normalize_media_group_id(
        media_group_id: Optional[str], msg_type: str
    ) -> Optional[str]:
        if not media_group_id:
            return None
        if msg_type not in ("image", "video"):
            return None
        gid = str(media_group_id).strip()[:64]
        return gid or None

    def send_message(
        self,
        conversation_id: int,
        sender_id: int,
        msg_type: str,
        content: str,
        media_url: Optional[str] = None,
        reply_to_message_id: Optional[int] = None,
        client_message_id: Optional[str] = None,
        inline_keyboard_json: Optional[str] = None,
        silent: bool = False,
        disable_webpage_preview: bool = False,
        media_group_id: Optional[str] = None,
        has_spoiler: bool = False,
        is_paid: bool = False,
        price_stars: int = 0,
        effect_id: Optional[str] = None,
        topic_id: Optional[int] = None,
        is_anonymous: bool = False,
        notify: bool = True,
    ) -> tuple[Message, bool]:
        from app.services.emoji_pack_service import (
            EmojiPackService,
            prepare_send_content,
        )

        emoji = EmojiPackService(self.db)
        content = prepare_send_content(emoji, sender_id, msg_type, content)
        for part in _inline_keyboard_text_parts(inline_keyboard_json):
            emoji.require_send_tokens(sender_id, part)
        if client_message_id:
            existing = (
                self.db.query(Message)
                .filter(
                    Message.conversation_id == conversation_id,
                    Message.sender_id == sender_id,
                    Message.client_message_id == client_message_id,
                )
                .first()
            )
            if existing:
                return existing, False

        from app.services.anonymous_admin import can_send_anonymously

        effect = self._normalize_send_effect(effect_id, sender_id)
        resolved_topic_id = self._resolve_topic_for_send(conversation_id, topic_id)

        conv = self._validate_message_payload(
            conversation_id=conversation_id,
            sender_id=sender_id,
            msg_type=msg_type,
            content=content,
            media_url=media_url,
            reply_to_message_id=reply_to_message_id,
        )
        anonymous = bool(is_anonymous)
        if anonymous:
            is_group = bool(conv and conv.type == "group")
            is_admin = bool(
                is_group and self._is_group_admin(conversation_id, sender_id)
            )
            if not can_send_anonymously(is_group=is_group, is_admin=is_admin):
                raise ValueError("anonymous_not_allowed")
        group_id = self._normalize_media_group_id(media_group_id, msg_type)
        paid = bool(is_paid) and msg_type in ("image", "video", "file")
        stars = max(0, int(price_stars or 0)) if paid else 0
        spoiler = bool(has_spoiler) and msg_type in ("image", "video")

        msg = Message(
            conversation_id=conversation_id,
            sender_id=sender_id,
            type=msg_type,
            content=content.strip() if content else "",
            media_url=media_url,
            reply_to_message_id=reply_to_message_id,
            client_message_id=client_message_id,
            inline_keyboard_json=inline_keyboard_json,
            disable_webpage_preview=bool(disable_webpage_preview),
            media_group_id=group_id,
            has_spoiler=spoiler,
            is_paid=paid,
            price_stars=stars,
            effect_id=effect,
            topic_id=resolved_topic_id,
            is_anonymous=anonymous,
        )
        self.db.add(msg)

        if conv:
            now = datetime.now(timezone.utc).replace(tzinfo=None)
            conv.updated_at = now
            if conv.type == "group":
                member = self._get_member_record(conversation_id, sender_id)
                if member is not None:
                    member.last_group_message_at = now

        self.db.flush()
        # Charge paid-DM fee BEFORE notify so 402 never sends ghost pushes.
        self._charge_direct_paid_message_fee(
            conversation_id=conversation_id,
            sender_id=sender_id,
            msg=msg,
            is_new=True,
            conv=conv,
        )
        # Push/FCM is optional: live HTTP send emits WS first, then notifies
        # in a background session so the first tap is not blocked by FCM.
        self._last_auto_replies = []
        if conv and conv.type == "direct":
            from app.services.business_profile_service import maybe_auto_reply

            self._last_auto_replies = maybe_auto_reply(self.db, conv, sender_id)
        if notify:
            self._notify_new_message(
                msg,
                sender_id=sender_id,
                msg_type=msg_type,
                content=content,
                silent=bool(silent),
            )
        return msg, True

    def take_auto_replies(self) -> list[Message]:
        rows = list(getattr(self, "_last_auto_replies", []) or [])
        self._last_auto_replies = []
        return rows

    def _charge_direct_paid_message_fee(
        self,
        *,
        conversation_id: int,
        sender_id: int,
        msg: Message,
        is_new: bool,
        conv: Optional[Conversation] = None,
    ) -> None:
        """Charge paid-DM Stars for live and scheduled sends. Undoes msg on 402."""
        if not is_new:
            return
        if conv is None:
            conv = (
                self.db.query(Conversation)
                .filter(Conversation.id == conversation_id)
                .first()
            )
        if not conv or conv.type != "direct":
            return
        peer_id = (
            conv.direct_user_high_id
            if conv.direct_user_low_id == sender_id
            else conv.direct_user_low_id
        )
        if not peer_id:
            return
        from fastapi import HTTPException

        from app.services.paid_features_service import PaidFeaturesService

        try:
            PaidFeaturesService(self.db).charge_paid_message_fee(
                sender_id,
                int(peer_id),
                conversation_id=conversation_id,
                message_id=msg.id,
                media_group_id=getattr(msg, "media_group_id", None),
            )
        except HTTPException as e:
            # Don't deliver unpaid scheduled/live content.
            self.db.delete(msg)
            self.db.flush()
            if int(getattr(e, "status_code", 0) or 0) == 402:
                raise ValueError("stars_required") from e
            raise ValueError("paid_message_fee_failed") from e

    def forward_message(
        self,
        *,
        target_conversation_id: int,
        source_conversation_id: int,
        message_id: int,
        sender_id: int,
        as_copy: bool = False,
    ) -> Message:
        if not self._is_member(target_conversation_id, sender_id):
            raise ValueError("forbidden")
        if not self._is_member(source_conversation_id, sender_id):
            raise ValueError("forbidden")

        src = (
            self.db.query(Message)
            .filter(
                Message.id == message_id,
                Message.conversation_id == source_conversation_id,
                Message.deleted_at.is_(None),
            )
            .first()
        )
        if not src:
            raise ValueError("not_found")

        source_conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == source_conversation_id)
            .first()
        )
        if source_conv is not None and bool(
            getattr(source_conv, "protect_content", False)
        ):
            raise ValueError("protect_content")

        content = src.content or ""
        media_url = src.media_url
        if src.type == "poll":
            # Clone as a fresh poll (no votes / closed state).
            from app.services.chat_poll_service import (
                build_poll_content,
                parse_poll_content,
            )

            data = parse_poll_content(content)
            if not data:
                raise ValueError("empty_poll")
            poll = data.get("poll") or {}
            texts = [
                str(o.get("text") or "").strip()
                for o in (poll.get("options") or [])
                if isinstance(o, dict)
            ]
            texts = [t for t in texts if t]
            content = build_poll_content(
                poll.get("question") or "",
                texts,
                description=poll.get("description") or "",
                settings=poll.get("settings")
                if isinstance(poll.get("settings"), dict)
                else None,
            )
            media_url = None

        # Paid media: only sender or unlocker may forward (Telegram Stars parity).
        src_paid = bool(getattr(src, "is_paid", False))
        src_price = int(getattr(src, "price_stars", 0) or 0) if src_paid else 0
        if src_paid:
            if int(src.sender_id) != int(sender_id):
                from app.services.paid_features_service import PaidFeaturesService

                if not PaidFeaturesService(self.db).has_unlocked_message(
                    sender_id, src
                ):
                    raise ValueError("paid_media_locked")
            if not media_url:
                raise ValueError("paid_media_locked")
        msg, _ = self.send_message(
            conversation_id=target_conversation_id,
            sender_id=sender_id,
            msg_type=src.type,
            content=content,
            media_url=media_url,
            is_paid=src_paid,
            price_stars=src_price,
            media_group_id=getattr(src, "media_group_id", None),
            has_spoiler=bool(getattr(src, "has_spoiler", False)),
            notify=False,
        )
        if as_copy:
            if not self._has_feature(sender_id, "hide_forward"):
                raise ValueError("hide_forward_required")
            msg.forward_from_user_id = None
            msg.forward_from_name = None
            msg.forwarded_from_message_id = None
        else:
            # Preserve original author when re-forwarding an already-forwarded msg.
            if getattr(src, "forward_from_user_id", None):
                forward_user_id = src.forward_from_user_id
                forward_name = src.forward_from_name
            else:
                forward_user_id = src.sender_id
                author = self.db.query(User).filter(User.id == src.sender_id).first()
                if author:
                    forward_name = (
                        (author.name or "").strip()
                        or (author.username or "").strip()
                        or "Пользователь"
                    )
                else:
                    forward_name = "Пользователь"
            from app.services.emoji_pack_service import preview_text_with_custom_emoji

            raw_forward = (forward_name or "").strip()
            msg.forward_from_user_id = forward_user_id
            msg.forward_from_name = (
                preview_text_with_custom_emoji(raw_forward, limit=120)
                if raw_forward
                else None
            )
            msg.forwarded_from_message_id = src.id
        self.db.flush()
        return msg

    @staticmethod
    def _content_mentions_user(
        content: str,
        user: User,
        *,
        is_admin: bool = False,
    ) -> bool:
        """True when content @-mentions this user (@username, @idN, @all, @admin)."""
        if not content:
            return False
        import re

        handles = {
            m.group(1).lower()
            for m in re.finditer(r"(?<!\w)@([a-zA-Z0-9_]{2,})", content)
        }
        id_mentions = {
            int(m.group(1))
            for m in re.finditer(r"(?<!\w)@id(\d+)\b", content)
        }
        if user.id in id_mentions:
            return True
        if "all" in handles:
            return True
        if is_admin and ("admin" in handles or "admins" in handles):
            return True
        uname = (user.username or "").lstrip("@").lower()
        return bool(uname and uname in handles)

    def _mentioned_member_ids(self, conversation_id: int, content: str) -> set[int]:
        if not content:
            return set()
        import re

        handles = {
            m.group(1).lower()
            for m in re.finditer(r"(?<!\w)@([a-zA-Z0-9_]{2,})", content)
        }
        id_mentions = {
            int(m.group(1))
            for m in re.finditer(r"(?<!\w)@id(\d+)\b", content)
        }
        if not handles and not id_mentions:
            return set()
        members = (
            self.db.query(ConversationMember)
            .filter(ConversationMember.conversation_id == conversation_id)
            .all()
        )
        if not members:
            return set()
        member_ids = [m.user_id for m in members]
        member_id_set = set(member_ids)
        out: set[int] = set()
        for uid in id_mentions:
            if uid in member_id_set:
                out.add(uid)
        if "all" in handles:
            out.update(member_ids)
        if "admin" in handles or "admins" in handles:
            conv = (
                self.db.query(Conversation)
                .filter(Conversation.id == conversation_id)
                .first()
            )
            for m in members:
                if m.is_admin or (
                    conv is not None and conv.created_by_user_id == m.user_id
                ):
                    out.add(m.user_id)
        users = (
            self.db.query(User)
            .filter(
                User.id.in_(member_ids),
                User.username.isnot(None),
                User.deleted_at.is_(None),
            )
            .all()
        )
        for u in users:
            uname = (u.username or "").lstrip("@").lower()
            if uname and uname in handles:
                out.add(u.id)
        return out

    def _notify_new_message(
        self,
        msg: Message,
        *,
        sender_id: int,
        msg_type: str,
        content: str,
        silent: bool = False,
    ) -> None:
        # Telegram «отправка без звука»: сообщение доставляется, push/inbox не шлём.
        if silent:
            return
        conversation_id = msg.conversation_id
        members = (
            self.db.query(ConversationMember)
            .filter(ConversationMember.conversation_id == conversation_id)
            .all()
        )
        sender = self.db.query(User).filter(User.id == sender_id).first()
        from app.services.emoji_pack_service import preview_text_with_custom_emoji

        sender_label = (
            ((sender.name or "").strip() or (sender.username or "").strip() or "Пользователь")
            if sender
            else "Пользователь"
        )
        sender_name = preview_text_with_custom_emoji(sender_label, limit=80)
        if msg_type == "voice":
            preview = "🎤 Голосовое"
        elif msg_type == "image":
            preview = "📷 Фото"
        elif msg_type == "file":
            name = (content or "").strip() or "Файл"
            preview = f"📎 {preview_text_with_custom_emoji(name, limit=80)}"
        elif msg_type == "video":
            preview = "🎬 Видео"
        elif msg_type == "video_note":
            preview = "⭕ Видеосообщение"
        elif msg_type == "sticker":
            preview = "🧩 Стикер"
        elif msg_type == "location":
            preview = "📍 Геопозиция"
        elif msg_type == "story_reply":
            preview = "🖼 Ответ на сторис"
            try:
                import json as _json

                data = _json.loads(content or "{}")
                text = (data.get("text") or "").strip()
                if text:
                    from app.services.emoji_pack_service import (
                        preview_text_with_custom_emoji,
                    )

                    preview = f"🖼 {preview_text_with_custom_emoji(text, limit=100)}"
            except Exception:
                pass
        elif msg_type == "call":
            preview = "📞 Звонок"
            try:
                import json as _json

                data = _json.loads(content or "{}")
                status = (data.get("status") or "").strip()
                media = (data.get("media") or "voice").strip()
                is_video = media == "video"
                if status == "missed":
                    preview = "📞 Пропущенный видеозвонок" if is_video else "📞 Пропущенный звонок"
                elif status == "rejected":
                    preview = "📹 Видеозвонок · отклонён" if is_video else "📞 Звонок · отклонён"
                elif status == "cancelled":
                    preview = "📹 Видеозвонок · отменён" if is_video else "📞 Звонок · отменён"
                elif status == "ended":
                    preview = "📹 Видеозвонок" if is_video else "📞 Звонок"
            except Exception:
                pass
        elif msg_type == "poll":
            from app.services.chat_poll_service import poll_preview_text

            preview = poll_preview_text(content)
        elif msg_type == "checklist":
            from app.services.chat_checklist_service import checklist_preview_text

            preview = checklist_preview_text(content)
        else:
            preview = preview_text_with_custom_emoji(content) if content else ""

        mentioned_ids = self._mentioned_member_ids(conversation_id, content or "")
        mentioned_ids.discard(sender_id)
        notif = NotificationService(self.db)
        for m in members:
            if m.user_id == sender_id:
                continue
            is_muted = self._expire_mute_if_needed(m)
            mode = self._normalize_notify_mode(
                getattr(m, "notify_mode", None),
                muted=is_muted,
            )
            # Fully silent: no messages and no @mentions.
            if mode == "none":
                continue
            if m.user_id in mentioned_ids:
                notif.notify_chat_mention(
                    mentioned_user_id=m.user_id,
                    mentioner_id=sender_id,
                    conversation_id=conversation_id,
                    message_id=msg.id,
                    mentioner_name=sender_name,
                    preview=preview,
                )
                continue
            # Mentions-only mute (Telegram default): skip regular messages.
            if mode == "mentions" or is_muted:
                continue
            notif.create_notification(
                user_id=m.user_id,
                type="message",
                title=sender_name,
                body=preview,
                entity_type="conversation",
                entity_id=conversation_id,
                actor_id=sender_id,
                data={
                    "conversation_id": conversation_id,
                    "message_id": msg.id,
                    "route": "chat",
                },
            )

    def _message_preview_text(self, msg: Message) -> str:
        msg_type = msg.type or "text"
        content = msg.content or ""
        if msg_type == "voice":
            return "🎤 Голосовое"
        if msg_type == "image":
            return "📷 Фото"
        if msg_type == "file":
            from app.services.emoji_pack_service import preview_text_with_custom_emoji

            name = (content or "").strip() or "Файл"
            return f"📎 {preview_text_with_custom_emoji(name, limit=80)}"
        if msg_type == "checklist":
            from app.services.chat_checklist_service import checklist_preview_text

            return checklist_preview_text(content)
        if msg_type == "video":
            return "🎬 Видео"
        if msg_type == "video_note":
            return "⭕ Видеосообщение"
        if msg_type == "sticker":
            return "🧩 Стикер"
        if msg_type == "location":
            return "📍 Геопозиция"
        if msg_type == "poll":
            from app.services.chat_poll_service import poll_preview_text

            return poll_preview_text(content)
        from app.services.emoji_pack_service import preview_text_with_custom_emoji

        return preview_text_with_custom_emoji(content)

    def notify_pinned_message(
        self,
        *,
        conversation_id: int,
        actor_id: int,
        message_id: int,
    ) -> int:
        """Push/inbox peers about a newly pinned message (Telegram notify)."""
        members = (
            self.db.query(ConversationMember)
            .filter(ConversationMember.conversation_id == conversation_id)
            .all()
        )
        from app.services.emoji_pack_service import preview_text_with_custom_emoji

        actor = self.db.query(User).filter(User.id == actor_id).first()
        actor_label = (
            ((actor.name or "").strip() or (actor.username or "").strip() or "Пользователь")
            if actor
            else "Пользователь"
        )
        actor_name = preview_text_with_custom_emoji(actor_label, limit=80)
        msg = (
            self.db.query(Message)
            .filter(
                Message.id == message_id,
                Message.conversation_id == conversation_id,
                Message.deleted_at.is_(None),
            )
            .first()
        )
        preview = self._message_preview_text(msg) if msg else "Сообщение"
        body = f"📌 {preview}"
        notif = NotificationService(self.db)
        sent = 0
        for m in members:
            if m.user_id == actor_id:
                continue
            is_muted = self._expire_mute_if_needed(m)
            mode = self._normalize_notify_mode(
                getattr(m, "notify_mode", None),
                muted=is_muted,
            )
            if mode == "none" or mode == "mentions" or is_muted:
                continue
            notif.create_notification(
                user_id=m.user_id,
                type="message",
                title=actor_name,
                body=body,
                entity_type="conversation",
                entity_id=conversation_id,
                actor_id=actor_id,
                data={
                    "conversation_id": conversation_id,
                    "message_id": message_id,
                    "route": "chat",
                    "action": "pin",
                },
            )
            sent += 1
        return sent

    def schedule_message(
        self,
        *,
        conversation_id: int,
        sender_id: int,
        msg_type: str,
        content: str,
        send_at: Optional[datetime] = None,
        send_when_online: bool = False,
        silent: bool = False,
        disable_webpage_preview: bool = False,
        media_group_id: Optional[str] = None,
        has_spoiler: bool = False,
        media_url: Optional[str] = None,
        reply_to_message_id: Optional[int] = None,
        client_message_id: Optional[str] = None,
        inline_keyboard_json: Optional[str] = None,
        effect_id: Optional[str] = None,
        topic_id: Optional[int] = None,
    ) -> ScheduledMessage:
        from app.services.emoji_pack_service import (
            EmojiPackService,
            prepare_send_content,
        )

        emoji = EmojiPackService(self.db)
        content = prepare_send_content(emoji, sender_id, msg_type, content)
        for part in _inline_keyboard_text_parts(inline_keyboard_json):
            emoji.require_send_tokens(sender_id, part)
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        target_user_id: Optional[int] = None
        if send_when_online:
            if not conv or conv.type != "direct":
                raise ValueError("when_online_direct_only")
            target_user_id = self.peer_user_id(conv, sender_id)
            send_at_naive = now
        else:
            if send_at is None:
                raise ValueError("invalid_send_at")
            if send_at.tzinfo is None:
                send_at_naive = send_at
            else:
                send_at_naive = send_at.astimezone(timezone.utc).replace(tzinfo=None)
            if send_at_naive <= now:
                raise ValueError("invalid_send_at")

        self._validate_message_payload(
            conversation_id=conversation_id,
            sender_id=sender_id,
            msg_type=msg_type,
            content=content,
            media_url=media_url,
            reply_to_message_id=reply_to_message_id,
        )
        effect = self._normalize_send_effect(effect_id, sender_id)
        resolved_topic_id = self._resolve_topic_for_send(conversation_id, topic_id)

        scheduled = ScheduledMessage(
            conversation_id=conversation_id,
            sender_id=sender_id,
            type=msg_type,
            content=content.strip() if content else "",
            media_url=media_url,
            reply_to_message_id=reply_to_message_id,
            client_message_id=client_message_id,
            inline_keyboard_json=inline_keyboard_json,
            send_at=send_at_naive,
            deliver_when_online=send_when_online,
            silent=bool(silent),
            disable_webpage_preview=bool(disable_webpage_preview),
            media_group_id=self._normalize_media_group_id(
                media_group_id, msg_type
            ),
            has_spoiler=bool(has_spoiler) and msg_type in ("image", "video"),
            effect_id=effect,
            topic_id=resolved_topic_id,
            target_user_id=target_user_id,
            status="pending",
        )
        self.db.add(scheduled)
        self.db.flush()
        return scheduled

    def list_scheduled_messages(
        self, conversation_id: int, user_id: int, limit: int = 100
    ) -> List[ScheduledMessage]:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        return (
            self.db.query(ScheduledMessage)
            .filter(
                ScheduledMessage.conversation_id == conversation_id,
                ScheduledMessage.sender_id == user_id,
                ScheduledMessage.status.in_(("pending", "failed")),
                ScheduledMessage.canceled_at.is_(None),
            )
            .order_by(
                ScheduledMessage.status.asc(),
                ScheduledMessage.send_at.asc(),
                ScheduledMessage.id.asc(),
            )
            .limit(limit)
            .all()
        )

    def cancel_scheduled_message(
        self, conversation_id: int, scheduled_message_id: int, user_id: int
    ) -> ScheduledMessage:
        item = (
            self.db.query(ScheduledMessage)
            .filter(
                ScheduledMessage.id == scheduled_message_id,
                ScheduledMessage.conversation_id == conversation_id,
                ScheduledMessage.sender_id == user_id,
            )
            .first()
        )
        if not item:
            raise ValueError("not_found")
        if item.status not in ("pending", "failed") or item.canceled_at is not None:
            raise ValueError("already_processed")
        item.status = "canceled"
        item.canceled_at = datetime.now(timezone.utc).replace(tzinfo=None)
        return item

    def reschedule_message(
        self,
        conversation_id: int,
        scheduled_message_id: int,
        user_id: int,
        send_at: Optional[datetime] = None,
        content: Optional[str] = None,
    ) -> ScheduledMessage:
        item = (
            self.db.query(ScheduledMessage)
            .filter(
                ScheduledMessage.id == scheduled_message_id,
                ScheduledMessage.conversation_id == conversation_id,
                ScheduledMessage.sender_id == user_id,
            )
            .first()
        )
        if not item:
            raise ValueError("not_found")
        if item.status not in ("pending", "failed") or item.canceled_at is not None:
            raise ValueError("already_processed")

        if content is not None:
            text = (content or "").strip()
            if item.type == "text":
                if not text:
                    raise ValueError("empty_content")
                from app.services.emoji_pack_service import (
                    EmojiPackService,
                    prepare_send_content,
                )

                text = prepare_send_content(
                    EmojiPackService(self.db), user_id, item.type, text
                )
                item.content = text[:4000]
            elif item.type in ("image", "video", "video_note", "file"):
                from app.services.emoji_pack_service import EmojiPackService

                EmojiPackService(self.db).require_send_tokens(user_id, text)
                item.content = text[:4000]
            else:
                raise ValueError("content_locked")

        if send_at is not None:
            if item.deliver_when_online:
                raise ValueError("online_delivery_locked")
            if send_at.tzinfo is None:
                send_at_naive = send_at
            else:
                send_at_naive = send_at.astimezone(timezone.utc).replace(tzinfo=None)
            now = datetime.now(timezone.utc).replace(tzinfo=None)
            if send_at_naive <= now:
                raise ValueError("invalid_send_at")
            item.send_at = send_at_naive

        if send_at is None and content is None:
            raise ValueError("empty_patch")
        if item.status == "failed":
            item.status = "pending"
            item.error_text = None
        return item

    def dispatch_scheduled_messages(
        self, conversation_id: int, limit: int = 30
    ) -> List[Message]:
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        fetch_limit = max(limit * 4, limit)
        due = (
            self.db.query(ScheduledMessage)
            .filter(
                ScheduledMessage.conversation_id == conversation_id,
                ScheduledMessage.status == "pending",
                ScheduledMessage.canceled_at.is_(None),
            )
            .order_by(ScheduledMessage.send_at.asc(), ScheduledMessage.id.asc())
            .limit(fetch_limit)
            .all()
        )
        return self._dispatch_scheduled_items(due, now=now, limit=limit)

    def dispatch_due_scheduled_messages(self, limit: int = 40) -> List[Message]:
        """Global dispatcher for due/online scheduled messages (background loop)."""
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        fetch_limit = max(limit * 4, limit)
        due = (
            self.db.query(ScheduledMessage)
            .filter(
                ScheduledMessage.status == "pending",
                ScheduledMessage.canceled_at.is_(None),
                or_(
                    ScheduledMessage.deliver_when_online.is_(True),
                    ScheduledMessage.send_at <= now,
                ),
            )
            .order_by(ScheduledMessage.send_at.asc(), ScheduledMessage.id.asc())
            .limit(fetch_limit)
            .all()
        )
        return self._dispatch_scheduled_items(due, now=now, limit=limit)

    @staticmethod
    def _scheduled_fail_text(code: str) -> str:
        mapping = {
            "pack_purchase_required": "Нужно купить пак",
            "custom_emoji_denied": "Эмодзи недоступен — купите пак",
            "custom_emoji_required": "Кастомные эмодзи с уровня 69",
            "premium_sticker": "Нужны премиум-стикеры",
            "paid_message_fee_failed": "Недостаточно звёзд",
        }
        return mapping.get(code, code)[:120]

    def _dispatch_scheduled_items(
        self,
        due: List[ScheduledMessage],
        *,
        now: datetime,
        limit: int,
    ) -> List[Message]:
        sent_messages: List[Message] = []
        for item in due:
            if len(sent_messages) >= limit:
                break
            if item.deliver_when_online:
                if not item.target_user_id:
                    continue
                peer = (
                    self.db.query(User.last_seen_at)
                    .filter(User.id == item.target_user_id)
                    .first()
                )
                last_seen = peer.last_seen_at if peer else None
                if not last_seen:
                    continue
                if (now - last_seen).total_seconds() > 180:
                    continue
            elif item.send_at > now:
                continue
            try:
                content = item.content
                if item.type == "poll":
                    from app.services.chat_poll_service import rebase_poll_closes_at

                    content = rebase_poll_closes_at(content)
                msg, _is_new = self.send_message(
                    conversation_id=item.conversation_id,
                    sender_id=item.sender_id,
                    msg_type=item.type,
                    content=content,
                    media_url=item.media_url,
                    reply_to_message_id=item.reply_to_message_id,
                    client_message_id=item.client_message_id,
                    inline_keyboard_json=item.inline_keyboard_json,
                    silent=bool(getattr(item, "silent", False)),
                    disable_webpage_preview=bool(
                        getattr(item, "disable_webpage_preview", False)
                    ),
                    media_group_id=getattr(item, "media_group_id", None),
                    has_spoiler=bool(getattr(item, "has_spoiler", False)),
                    effect_id=getattr(item, "effect_id", None),
                    topic_id=getattr(item, "topic_id", None),
                )
                # Paid-DM fee charged inside send_message (before notify).
                item.status = "sent"
                item.sent_message_id = msg.id
                item.sent_at = datetime.now(timezone.utc).replace(tzinfo=None)
                item.error_text = None
                sent_messages.append(msg)
            except ValueError as e:
                item.status = "failed"
                item.error_text = self._scheduled_fail_text(str(e))
        return sent_messages

    def purge_due_auto_deleted_messages(
        self, limit_conversations: int = 80
    ) -> Dict[int, List[int]]:
        """Purge TTL-expired messages across chats that have auto-delete enabled."""
        conv_ids = (
            self.db.query(Conversation.id)
            .filter(Conversation.auto_delete_seconds > 0)
            .order_by(Conversation.id.asc())
            .limit(max(1, int(limit_conversations)))
            .all()
        )
        purged: Dict[int, List[int]] = {}
        for (cid,) in conv_ids:
            ids = self.purge_auto_deleted_messages(cid)
            if ids:
                purged[cid] = ids
        return purged

    def delete_message(
        self,
        conversation_id: int,
        message_id: int,
        user_id: int,
        *,
        scope: str = "all",
    ) -> str:
        """Delete message. Returns 'me' or 'all' for event fanout."""
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        msg = (
            self.db.query(Message)
            .filter(
                Message.id == message_id,
                Message.conversation_id == conversation_id,
                Message.deleted_at.is_(None),
            )
            .first()
        )
        if not msg:
            raise ValueError("not_found")

        normalized = (scope or "all").strip().lower()
        if normalized not in ("me", "all"):
            raise ValueError("bad_scope")

        # Anyone can hide for themselves.
        if normalized == "me":
            existing = (
                self.db.query(MessageHide)
                .filter(
                    MessageHide.message_id == message_id,
                    MessageHide.user_id == user_id,
                )
                .first()
            )
            if not existing:
                self.db.add(
                    MessageHide(message_id=message_id, user_id=user_id)
                )
            return "me"

        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        is_admin_delete = bool(
            conv
            and conv.type == "group"
            and self._can_delete_group_messages(conversation_id, user_id)
        )
        if msg.sender_id != user_id and not is_admin_delete:
            raise ValueError("forbidden")
        # Sender: 48h window. Group admins with delete right: no age limit.
        if not is_admin_delete:
            created = msg.created_at
            if created is not None:
                created_aware = created
                if created_aware.tzinfo is None:
                    created_aware = created_aware.replace(tzinfo=timezone.utc)
                age = datetime.now(timezone.utc) - created_aware.astimezone(
                    timezone.utc
                )
                if age.total_seconds() > 48 * 3600:
                    raise ValueError("too_old")
        msg.deleted_at = datetime.now(timezone.utc).replace(tzinfo=None)
        (
            self.db.query(ConversationPinnedMessage)
            .filter(ConversationPinnedMessage.message_id == message_id)
            .delete(synchronize_session=False)
        )
        if conv:
            self._sync_legacy_pinned_slot(conv)
        return "all"

    def _get_active_message(
        self, conversation_id: int, message_id: int, user_id: int
    ) -> Message:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        msg = (
            self.db.query(Message)
            .filter(
                Message.id == message_id,
                Message.conversation_id == conversation_id,
                Message.deleted_at.is_(None),
            )
            .first()
        )
        if not msg:
            raise ValueError("not_found")
        return msg

    def edit_message(
        self, conversation_id: int, message_id: int, user_id: int, content: str
    ) -> Message:
        msg = self._get_active_message(conversation_id, message_id, user_id)
        if msg.sender_id != user_id:
            raise ValueError("forbidden")
        if msg.type not in ("text", "image", "video", "file"):
            raise ValueError("not_editable")
        clean = (content or "").strip()
        if msg.type == "text" and not clean:
            raise ValueError("empty_message")
        from app.services.emoji_pack_service import (
            EmojiPackService,
            prepare_send_content,
        )

        clean = prepare_send_content(
            EmojiPackService(self.db), user_id, msg.type, clean
        )
        previous = (msg.content or "")[:4000]
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        if previous != clean[:4000]:
            self.db.add(
                MessageEditHistory(
                    message_id=msg.id,
                    editor_id=user_id,
                    previous_content=previous,
                    edited_at=now,
                )
            )
        msg.content = clean[:4000]
        msg.edited_at = now
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        if conv:
            conv.updated_at = now
        return msg

    def list_message_edit_history(
        self, conversation_id: int, message_id: int, user_id: int
    ) -> Tuple[Message, List[MessageEditHistory]]:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        msg = (
            self.db.query(Message)
            .filter(
                Message.id == message_id,
                Message.conversation_id == conversation_id,
                Message.deleted_at.is_(None),
            )
            .first()
        )
        if not msg:
            raise ValueError("not_found")
        rows = (
            self.db.query(MessageEditHistory)
            .filter(MessageEditHistory.message_id == message_id)
            .order_by(
                MessageEditHistory.edited_at.desc(),
                MessageEditHistory.id.desc(),
            )
            .limit(50)
            .all()
        )
        return msg, rows

    def reactions_for_messages(
        self, message_ids: List[int], viewer_id: int
    ) -> Dict[int, List[dict]]:
        if not message_ids:
            return {}
        rows = (
            self.db.query(MessageReaction)
            .filter(MessageReaction.message_id.in_(message_ids))
            .all()
        )
        grouped: Dict[int, Dict[str, dict]] = {}
        for row in rows:
            by_emoji = grouped.setdefault(row.message_id, {})
            entry = by_emoji.setdefault(
                row.emoji,
                {
                    "emoji": row.emoji,
                    "count": 0,
                    "reacted_by_me": False,
                    "stars_total": 0,
                },
            )
            entry["count"] += 1
            entry["stars_total"] = int(entry.get("stars_total") or 0) + int(
                getattr(row, "stars_amount", 0) or 0
            )
            if row.user_id == viewer_id:
                entry["reacted_by_me"] = True
        return {
            mid: list(by_emoji.values())
            for mid, by_emoji in grouped.items()
        }

    def message_reaction_users(
        self,
        conversation_id: int,
        message_id: int,
        viewer_id: int,
        emoji: Optional[str] = None,
    ) -> list[tuple[str, User, int]]:
        """Per-user reactions for a message (Telegram «кто поставил»)."""
        if not self._is_member(conversation_id, viewer_id):
            raise ValueError("forbidden")
        msg = (
            self.db.query(Message)
            .filter(
                Message.id == message_id,
                Message.conversation_id == conversation_id,
                Message.deleted_at.is_(None),
            )
            .first()
        )
        if not msg:
            raise ValueError("not_found")
        query = (
            self.db.query(MessageReaction, User)
            .join(User, User.id == MessageReaction.user_id)
            .filter(
                MessageReaction.message_id == message_id,
                User.deleted_at.is_(None),
            )
        )
        clean = (emoji or "").strip()
        if clean:
            query = query.filter(MessageReaction.emoji == clean)
        rows = query.all()
        # Telegram paid reactions: top senders first by ★, then earliest.
        rows.sort(
            key=lambda pair: (
                -int(getattr(pair[0], "stars_amount", 0) or 0),
                pair[0].created_at or datetime.min,
                int(pair[0].id or 0),
            )
        )
        return [
            (row.emoji, user, int(getattr(row, "stars_amount", 0) or 0))
            for row, user in rows
        ]

    def set_message_reaction(
        self,
        conversation_id: int,
        message_id: int,
        user_id: int,
        emoji: str,
        stars_amount: int = 0,
    ) -> Optional[str]:
        self._get_active_message(conversation_id, message_id, user_id)
        clean = emoji.strip()
        if not clean or len(clean) > 32:
            raise ValueError("invalid_emoji")
        from app.core.entitlements import (
            EXCLUSIVE_CHAT_REACTIONS,
            FREE_CHAT_REACTIONS,
        )
        from app.services.emoji_pack_service import EmojiPackService
        from app.services.subscription_service import SubscriptionService

        custom = EmojiPackService(self.db).require_reaction(user_id, clean)
        if custom:
            clean = custom
        billing = SubscriptionService(self.db)
        if custom:
            pass
        elif clean in EXCLUSIVE_CHAT_REACTIONS:
            if not (
                billing.has_feature(user_id, "exclusive_reactions")
                or billing.has_feature(user_id, "any_emoji_reactions")
            ):
                raise ValueError("exclusive_reaction")
        elif clean not in FREE_CHAT_REACTIONS and not billing.has_feature(
            user_id, "any_emoji_reactions"
        ):
            raise ValueError("any_emoji_reaction")
        stars = max(0, int(stars_amount or 0))
        existing = (
            self.db.query(MessageReaction)
            .filter(
                MessageReaction.message_id == message_id,
                MessageReaction.user_id == user_id,
            )
            .first()
        )
        if existing:
            if existing.emoji == clean and stars <= 0:
                self.db.delete(existing)
                return None
            existing.emoji = clean
            if stars > 0:
                existing.stars_amount = int(existing.stars_amount or 0) + stars
            return clean
        self.db.add(
            MessageReaction(
                message_id=message_id,
                user_id=user_id,
                emoji=clean,
                stars_amount=stars,
            )
        )
        return clean

    def remove_message_reaction(
        self, conversation_id: int, message_id: int, user_id: int
    ) -> bool:
        self._get_active_message(conversation_id, message_id, user_id)
        row = (
            self.db.query(MessageReaction)
            .filter(
                MessageReaction.message_id == message_id,
                MessageReaction.user_id == user_id,
            )
            .first()
        )
        if not row:
            return False
        self.db.delete(row)
        return True

    PIN_LIMIT = 5
    PIN_LIMIT_PLUS = 20
    FOLDER_LIMIT = 10
    FOLDER_LIMIT_PLUS = 50
    PINNED_CHAT_LIMIT = 5
    PINNED_CHAT_LIMIT_PLUS = 20

    def _has_feature(self, user_id: int, slug: str) -> bool:
        try:
            from app.services.subscription_service import SubscriptionService

            return SubscriptionService(self.db).has_feature(int(user_id), slug)
        except Exception:
            return False

    def _pin_limit_for(self, user_id: int) -> int:
        return self.PIN_LIMIT_PLUS if self._has_feature(user_id, "extra_pins") else self.PIN_LIMIT

    def _folder_limit_for(self, user_id: int) -> int:
        return (
            self.FOLDER_LIMIT_PLUS
            if self._has_feature(user_id, "extra_folders")
            else self.FOLDER_LIMIT
        )

    def _pinned_chat_limit_for(self, user_id: int) -> int:
        return (
            self.PINNED_CHAT_LIMIT_PLUS
            if self._has_feature(user_id, "extra_pinned_chats")
            else self.PINNED_CHAT_LIMIT
        )

    def _normalize_send_effect(self, effect_id: Optional[str], sender_id: int) -> Optional[str]:
        from app.services.message_effect_service import (
            is_premium_effect,
            normalize_effect_id,
        )

        effect = normalize_effect_id(effect_id)
        if effect and is_premium_effect(effect) and not self._has_feature(sender_id, "message_effects"):
            raise ValueError("effect_premium_required")
        return effect

    def _sync_legacy_pinned_slot(self, conv: Conversation) -> None:
        top = (
            self.db.query(ConversationPinnedMessage)
            .filter(ConversationPinnedMessage.conversation_id == conv.id)
            .order_by(ConversationPinnedMessage.pinned_at.desc())
            .first()
        )
        if top is None:
            conv.pinned_message_id = None
            conv.pinned_at = None
            conv.pinned_by_user_id = None
            return
        conv.pinned_message_id = top.message_id
        conv.pinned_at = top.pinned_at
        conv.pinned_by_user_id = top.pinned_by_user_id

    def set_pinned_message(
        self,
        conversation_id: int,
        user_id: int,
        message_id: Optional[int],
        pinned: bool,
    ) -> Optional[int]:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        if not conv:
            raise ValueError("not_found")
        # Groups: pin requires admin right. Direct/saved: any member.
        if conv.type == "group" and not self._can_pin_group_messages(
            conversation_id, user_id
        ):
            raise ValueError("forbidden")
        if not pinned:
            if message_id is None:
                # Clear all pins (legacy unpin without id).
                (
                    self.db.query(ConversationPinnedMessage)
                    .filter(
                        ConversationPinnedMessage.conversation_id
                        == conversation_id
                    )
                    .delete(synchronize_session=False)
                )
                self._sync_legacy_pinned_slot(conv)
                return None
            (
                self.db.query(ConversationPinnedMessage)
                .filter(
                    ConversationPinnedMessage.conversation_id == conversation_id,
                    ConversationPinnedMessage.message_id == message_id,
                )
                .delete(synchronize_session=False)
            )
            self._sync_legacy_pinned_slot(conv)
            return None
        if message_id is None:
            raise ValueError("missing_message")
        self._get_active_message(conversation_id, message_id, user_id)
        existing = (
            self.db.query(ConversationPinnedMessage)
            .filter(
                ConversationPinnedMessage.conversation_id == conversation_id,
                ConversationPinnedMessage.message_id == message_id,
            )
            .first()
        )
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        if existing:
            existing.pinned_at = now
            existing.pinned_by_user_id = user_id
        else:
            count = (
                self.db.query(func.count(ConversationPinnedMessage.id))
                .filter(
                    ConversationPinnedMessage.conversation_id == conversation_id
                )
                .scalar()
                or 0
            )
            if int(count) >= self._pin_limit_for(user_id):
                raise ValueError("pin_limit")
            self.db.add(
                ConversationPinnedMessage(
                    conversation_id=conversation_id,
                    message_id=message_id,
                    pinned_by_user_id=user_id,
                    pinned_at=now,
                )
            )
        self.db.flush()
        self._sync_legacy_pinned_slot(conv)
        return message_id

    def get_pinned_message(
        self, conversation_id: int, user_id: int
    ) -> Optional[Message]:
        msgs = self.list_pinned_messages(conversation_id, user_id)
        return msgs[0] if msgs else None

    def list_pinned_messages(
        self, conversation_id: int, user_id: int
    ) -> List[Message]:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        rows = (
            self.db.query(ConversationPinnedMessage, Message)
            .join(
                Message,
                Message.id == ConversationPinnedMessage.message_id,
            )
            .filter(
                ConversationPinnedMessage.conversation_id == conversation_id,
                Message.conversation_id == conversation_id,
                Message.deleted_at.is_(None),
            )
            .order_by(ConversationPinnedMessage.pinned_at.desc())
            .all()
        )
        # Drop orphan pin rows if any slipped through.
        out: List[Message] = []
        for pin_row, msg in rows:
            out.append(msg)
        if not out:
            conv = (
                self.db.query(Conversation)
                .filter(Conversation.id == conversation_id)
                .first()
            )
            if conv:
                self._sync_legacy_pinned_slot(conv)
        return out

    def upsert_draft(
        self,
        conversation_id: int,
        user_id: int,
        text: str,
        reply_to_message_id: Optional[int] = None,
    ) -> ConversationDraft:
        from app.services.emoji_pack_service import EmojiPackService

        EmojiPackService(self.db).require_send_tokens(user_id, text)
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        body = (text or "").strip()
        if not body and not reply_to_message_id:
            raise ValueError("empty_draft")
        reply_id = reply_to_message_id if reply_to_message_id and reply_to_message_id > 0 else None
        if reply_id is not None:
            exists = (
                self.db.query(Message.id)
                .filter(
                    Message.id == reply_id,
                    Message.conversation_id == conversation_id,
                    Message.deleted_at.is_(None),
                )
                .first()
            )
            if not exists:
                reply_id = None
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        row = (
            self.db.query(ConversationDraft)
            .filter(
                ConversationDraft.user_id == user_id,
                ConversationDraft.conversation_id == conversation_id,
            )
            .first()
        )
        if row is None:
            row = ConversationDraft(
                user_id=user_id,
                conversation_id=conversation_id,
                text=body[:4000],
                reply_to_message_id=reply_id,
                updated_at=now,
            )
            self.db.add(row)
        else:
            row.text = body[:4000]
            row.reply_to_message_id = reply_id
            row.updated_at = now
        return row

    def delete_draft(self, conversation_id: int, user_id: int) -> bool:
        row = (
            self.db.query(ConversationDraft)
            .filter(
                ConversationDraft.user_id == user_id,
                ConversationDraft.conversation_id == conversation_id,
            )
            .first()
        )
        if not row:
            return False
        self.db.delete(row)
        return True

    def get_draft(
        self, conversation_id: int, user_id: int
    ) -> Optional[ConversationDraft]:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        return (
            self.db.query(ConversationDraft)
            .filter(
                ConversationDraft.user_id == user_id,
                ConversationDraft.conversation_id == conversation_id,
            )
            .first()
        )

    def list_drafts(self, user_id: int) -> List[ConversationDraft]:
        return (
            self.db.query(ConversationDraft)
            .filter(ConversationDraft.user_id == user_id)
            .order_by(ConversationDraft.updated_at.desc())
            .all()
        )

    def mark_delivered(
        self, conversation_id: int, user_id: int, message_id: int
    ) -> None:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        member = (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == user_id,
            )
            .first()
        )
        if not member:
            return
        if (
            member.last_delivered_message_id is None
            or message_id > member.last_delivered_message_id
        ):
            member.last_delivered_message_id = message_id

    def mark_read(self, conversation_id: int, user_id: int, message_id: int) -> None:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        member = (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == user_id,
            )
            .first()
        )
        if not member:
            return
        if member.last_read_message_id is None or message_id > member.last_read_message_id:
            member.last_read_message_id = message_id
            member.last_read_at = datetime.now(timezone.utc).replace(tzinfo=None)
        # Read implies delivered (Telegram).
        if (
            member.last_delivered_message_id is None
            or message_id > member.last_delivered_message_id
        ):
            member.last_delivered_message_id = message_id
        # Opening/reading a chat clears unread reaction badges.
        member.reactions_seen_at = datetime.now(timezone.utc).replace(tzinfo=None)

    def mark_unread(self, conversation_id: int, user_id: int) -> Optional[int]:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        member = (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == user_id,
            )
            .first()
        )
        if not member:
            return None
        last_msg_id = (
            self.db.query(func.max(Message.id))
            .filter(
                Message.conversation_id == conversation_id,
                Message.deleted_at.is_(None),
            )
            .scalar()
        )
        if not last_msg_id:
            return member.last_read_message_id
        prev_id = (
            self.db.query(func.max(Message.id))
            .filter(
                Message.conversation_id == conversation_id,
                Message.id < last_msg_id,
                Message.deleted_at.is_(None),
            )
            .scalar()
        )
        member.last_read_message_id = prev_id
        return member.last_read_message_id

    def delete_conversation(
        self,
        conversation_id: int,
        user_id: int,
        *,
        also_for_peer: bool = False,
    ) -> Optional[int]:
        """Leave/delete a chat. Returns peer_user_id when also deleted for DM peer."""
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        if not conv:
            raise ValueError("not_found")
        if conv.type == "saved":
            raise ValueError("cannot_delete_saved")
        if conv.type == "group":
            if also_for_peer:
                raise ValueError("also_for_peer_direct_only")
            self.leave_group(conversation_id, user_id)
            return None
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        member = (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == user_id,
            )
            .first()
        )
        if not member:
            raise ValueError("not_found")
        peer_id: Optional[int] = None
        if also_for_peer:
            if conv.type != "direct":
                raise ValueError("also_for_peer_direct_only")
            peer_id = self.peer_user_id(conv, user_id)
            peer_member = self._get_member_record(conversation_id, peer_id)
            if peer_member is not None:
                self.db.delete(peer_member)
            else:
                peer_id = None
        self.db.delete(member)
        self.db.flush()
        if self._member_count(conversation_id) == 0:
            # Break pinned_message FK before CASCADE delete of messages.
            conv.pinned_message_id = None
            conv.pinned_at = None
            conv.pinned_by_user_id = None
            self.db.flush()
            self.db.delete(conv)
        return peer_id

    def total_unread(self, user_id: int) -> int:
        return (
            self.db.query(func.count(Message.id))
            .join(
                ConversationMember,
                and_(
                    ConversationMember.conversation_id == Message.conversation_id,
                    ConversationMember.user_id == user_id,
                    ConversationMember.archived_at.is_(None),
                ),
            )
            .filter(
                Message.sender_id != user_id,
                Message.deleted_at.is_(None),
                or_(
                    ConversationMember.last_read_message_id.is_(None),
                    Message.id > ConversationMember.last_read_message_id,
                ),
            )
            .scalar()
            or 0
        )

    # --- Contacts ---

    def list_contacts(self, owner_id: int) -> List[Contact]:
        return (
            self.db.query(Contact)
            .filter(Contact.owner_user_id == owner_id)
            .order_by(Contact.created_at.desc())
            .all()
        )

    def add_contact(self, owner_id: int, contact_user_id: int) -> Contact:
        if owner_id == contact_user_id:
            raise ValueError("self_contact")
        self._get_user_or_404(contact_user_id)
        existing = (
            self.db.query(Contact)
            .filter(
                Contact.owner_user_id == owner_id,
                Contact.contact_user_id == contact_user_id,
            )
            .first()
        )
        if existing:
            return existing
        row = Contact(owner_user_id=owner_id, contact_user_id=contact_user_id)
        self.db.add(row)
        self.db.flush()
        return row

    def remove_contact(self, owner_id: int, contact_user_id: int) -> bool:
        row = (
            self.db.query(Contact)
            .filter(
                Contact.owner_user_id == owner_id,
                Contact.contact_user_id == contact_user_id,
            )
            .first()
        )
        if not row:
            return False
        self.db.delete(row)
        return True

    def get_user_by_username(self, username: str) -> Optional[User]:
        handle = (username or "").strip().lstrip("@").lower()
        if len(handle) < 2:
            return None
        return (
            self.db.query(User)
            .filter(
                User.deleted_at.is_(None),
                User.banned_at.is_(None),
                func.lower(User.username) == handle,
            )
            .first()
        )

    def search_users(self, current_user_id: int, query: str, limit: int = 20) -> List[dict]:
        from app.services.search_normalization import (
            escaped_like_pattern,
            normalize_search_text,
        )

        q = query.strip().lstrip("@")
        if len(q) < 2:
            return []

        pattern = escaped_like_pattern(q)
        norm_q = normalize_search_text(q)
        norm_pattern = escaped_like_pattern(norm_q)
        name_normalized = func.replace(func.lower(User.name), "ё", "е")

        match_filters = [
            User.username.ilike(pattern, escape="\\"),
            User.name.ilike(pattern, escape="\\"),
            name_normalized.ilike(norm_pattern, escape="\\"),
            func.lower(func.coalesce(User.username, "")).ilike(
                norm_pattern, escape="\\"
            ),
        ]

        users = (
            self.db.query(User)
            .filter(
                User.deleted_at.is_(None),
                User.banned_at.is_(None),
                User.id != current_user_id,
                or_(*match_filters),
            )
            .order_by(User.username.asc().nullslast(), User.name.asc())
            .limit(limit)
            .all()
        )

        contact_ids = {
            c.contact_user_id
            for c in self.db.query(Contact.contact_user_id)
            .filter(Contact.owner_user_id == current_user_id)
            .all()
        }

        return [
            {"user": u, "is_contact": u.id in contact_ids}
            for u in users
        ]

    def match_users_by_phone_hashes(
        self,
        viewer_id: int,
        phone_hashes: List[str],
        limit: int = 200,
    ) -> List[dict]:
        if not phone_hashes:
            return []
        unique = list({h.strip().lower() for h in phone_hashes if h and len(h) == 64})[:500]
        if not unique:
            return []

        contact_ids = {
            c.contact_user_id
            for c in self.db.query(Contact.contact_user_id)
            .filter(Contact.owner_user_id == viewer_id)
            .all()
        }

        users = (
            self.db.query(User)
            .filter(
                User.phone_hash.in_(unique),
                User.id != viewer_id,
                User.deleted_at.is_(None),
                User.banned_at.is_(None),
            )
            .limit(limit)
            .all()
        )
        return [
            {"user": u, "is_contact": u.id in contact_ids}
            for u in users
        ]

    def _folder_payload(self, folder: ChatFolder) -> dict:
        items = (
            self.db.query(ChatFolderItem)
            .filter(ChatFolderItem.folder_id == folder.id)
            .all()
        )
        filters = {}
        if folder.filters_json:
            try:
                parsed = json.loads(folder.filters_json)
                if isinstance(parsed, dict):
                    filters = parsed
            except json.JSONDecodeError:
                filters = {}
        return {
            "id": folder.id,
            "name": folder.name,
            "icon": folder.icon,
            "position": folder.position,
            "conversation_ids": [
                i.conversation_id for i in items if i.conversation_id is not None
            ],
            "channel_ids": [i.channel_id for i in items if i.channel_id is not None],
            "filters": filters,
        }

    _PREMIUM_FOLDER_FILTER_KEYS = (
        "contacts",
        "non_contacts",
        "bots",
        "unread_only",
        "exclude_muted",
        "exclude_archived",
        "exclude_bots",
    )

    @staticmethod
    def _normalize_filters(filters: Optional[dict]) -> dict:
        if not filters:
            return {}
        return {
            "groups": bool(filters.get("groups")),
            "channels": bool(filters.get("channels")),
            "direct": bool(filters.get("direct") or filters.get("private")),
            # Telegram-like private chat subsets.
            "contacts": bool(filters.get("contacts")),
            "non_contacts": bool(filters.get("non_contacts")),
            "bots": bool(filters.get("bots")),
            "unread_only": bool(filters.get("unread_only")),
            "exclude_muted": bool(filters.get("exclude_muted")),
            "exclude_archived": bool(filters.get("exclude_archived")),
            "exclude_bots": bool(filters.get("exclude_bots")),
        }

    @classmethod
    def _folder_filters_need_premium(cls, filters: Optional[dict]) -> bool:
        if not filters:
            return False
        return any(bool(filters.get(key)) for key in cls._PREMIUM_FOLDER_FILTER_KEYS)

    def _require_folder_flex_options(
        self, user_id: int, icon: Optional[str], filters: Optional[dict]
    ) -> None:
        if self._folder_filters_need_premium(filters) and not self._has_feature(
            user_id, "folder_filters"
        ):
            raise ValueError("folder_filters_required")
        if (icon or "").strip() and not self._has_feature(user_id, "folder_icons"):
            raise ValueError("folder_icon_required")

    def list_folders(self, user_id: int) -> List[dict]:
        folders = (
            self.db.query(ChatFolder)
            .filter(ChatFolder.user_id == user_id)
            .order_by(ChatFolder.position.asc(), ChatFolder.id.asc())
            .all()
        )
        return [self._folder_payload(f) for f in folders]

    def create_folder(
        self,
        user_id: int,
        name: str,
        icon: Optional[str] = None,
        conversation_ids: Optional[List[int]] = None,
        channel_ids: Optional[List[int]] = None,
        filters: Optional[dict] = None,
    ) -> dict:
        name = (name or "").strip()
        if not name:
            raise ValueError("invalid_name")
        from app.services.emoji_pack_service import EmojiPackService

        EmojiPackService(self.db).require_send_tokens(user_id, name)
        EmojiPackService(self.db).require_send_tokens(user_id, icon)
        existing = (
            self.db.query(func.count(ChatFolder.id))
            .filter(ChatFolder.user_id == user_id)
            .scalar()
            or 0
        )
        if int(existing) >= self._folder_limit_for(user_id):
            raise ValueError("folder_limit")
        max_pos = (
            self.db.query(func.max(ChatFolder.position))
            .filter(ChatFolder.user_id == user_id)
            .scalar()
        )
        norm_filters = self._normalize_filters(filters)
        self._require_folder_flex_options(user_id, icon, norm_filters)
        folder = ChatFolder(
            user_id=user_id,
            name=name[:64],
            icon=(icon or "")[:32] or None,
            position=(max_pos or -1) + 1,
            filters_json=json.dumps(norm_filters) if norm_filters else None,
        )
        self.db.add(folder)
        self.db.flush()
        self._set_folder_items(folder, user_id, conversation_ids or [], channel_ids or [])
        self.db.flush()
        return self._folder_payload(folder)

    def _set_folder_items(
        self,
        folder: ChatFolder,
        user_id: int,
        conversation_ids: List[int],
        channel_ids: List[int],
    ) -> None:
        self.db.query(ChatFolderItem).filter(ChatFolderItem.folder_id == folder.id).delete()
        seen_conv: set[int] = set()
        for cid in conversation_ids:
            if cid in seen_conv:
                continue
            seen_conv.add(cid)
            if not self._is_member(cid, user_id):
                continue
            self.db.add(
                ChatFolderItem(folder_id=folder.id, conversation_id=cid, channel_id=None)
            )
        seen_ch: set[int] = set()
        for ch_id in channel_ids:
            if ch_id in seen_ch:
                continue
            seen_ch.add(ch_id)
            self.db.add(
                ChatFolderItem(folder_id=folder.id, conversation_id=None, channel_id=ch_id)
            )

    def update_folder(
        self,
        user_id: int,
        folder_id: int,
        name: Optional[str] = None,
        icon: Optional[str] = None,
        conversation_ids: Optional[List[int]] = None,
        channel_ids: Optional[List[int]] = None,
        filters: Optional[dict] = None,
    ) -> Optional[dict]:
        from app.services.emoji_pack_service import EmojiPackService

        if name is not None:
            EmojiPackService(self.db).require_send_tokens(user_id, name)
        if icon is not None:
            EmojiPackService(self.db).require_send_tokens(user_id, icon)
        folder = (
            self.db.query(ChatFolder)
            .filter(ChatFolder.id == folder_id, ChatFolder.user_id == user_id)
            .first()
        )
        if not folder:
            return None
        if name is not None:
            name = name.strip()
            if not name:
                raise ValueError("invalid_name")
            folder.name = name[:64]
        if icon is not None:
            self._require_folder_flex_options(user_id, icon, None)
            folder.icon = (icon or "")[:32] or None
        if filters is not None:
            norm_filters = self._normalize_filters(filters)
            self._require_folder_flex_options(user_id, None, norm_filters)
            folder.filters_json = json.dumps(norm_filters) if norm_filters else None
        if conversation_ids is not None or channel_ids is not None:
            current = self._folder_payload(folder)
            self._set_folder_items(
                folder,
                user_id,
                conversation_ids if conversation_ids is not None else current["conversation_ids"],
                channel_ids if channel_ids is not None else current["channel_ids"],
            )
        self.db.flush()
        return self._folder_payload(folder)

    def delete_folder(self, user_id: int, folder_id: int) -> bool:
        folder = (
            self.db.query(ChatFolder)
            .filter(ChatFolder.id == folder_id, ChatFolder.user_id == user_id)
            .first()
        )
        if not folder:
            return False
        self.db.delete(folder)
        return True

    def add_folder_item(
        self,
        user_id: int,
        folder_id: int,
        conversation_id: Optional[int] = None,
        channel_id: Optional[int] = None,
    ) -> Optional[dict]:
        folder = (
            self.db.query(ChatFolder)
            .filter(ChatFolder.id == folder_id, ChatFolder.user_id == user_id)
            .first()
        )
        if not folder:
            return None
        if conversation_id is not None:
            if not self._is_member(conversation_id, user_id):
                raise ValueError("not_member")
            exists = (
                self.db.query(ChatFolderItem.id)
                .filter(
                    ChatFolderItem.folder_id == folder_id,
                    ChatFolderItem.conversation_id == conversation_id,
                )
                .first()
            )
            if not exists:
                self.db.add(
                    ChatFolderItem(
                        folder_id=folder_id,
                        conversation_id=conversation_id,
                        channel_id=None,
                    )
                )
        elif channel_id is not None:
            exists = (
                self.db.query(ChatFolderItem.id)
                .filter(
                    ChatFolderItem.folder_id == folder_id,
                    ChatFolderItem.channel_id == channel_id,
                )
                .first()
            )
            if not exists:
                self.db.add(
                    ChatFolderItem(
                        folder_id=folder_id,
                        conversation_id=None,
                        channel_id=channel_id,
                    )
                )
        else:
            raise ValueError("invalid_item")
        self.db.flush()
        return self._folder_payload(folder)

    def remove_folder_item(
        self,
        user_id: int,
        folder_id: int,
        conversation_id: Optional[int] = None,
        channel_id: Optional[int] = None,
    ) -> Optional[dict]:
        folder = (
            self.db.query(ChatFolder)
            .filter(ChatFolder.id == folder_id, ChatFolder.user_id == user_id)
            .first()
        )
        if not folder:
            return None
        q = self.db.query(ChatFolderItem).filter(ChatFolderItem.folder_id == folder_id)
        if conversation_id is not None:
            q = q.filter(ChatFolderItem.conversation_id == conversation_id)
        elif channel_id is not None:
            q = q.filter(ChatFolderItem.channel_id == channel_id)
        else:
            raise ValueError("invalid_item")
        q.delete(synchronize_session=False)
        self.db.flush()
        return self._folder_payload(folder)

    def reorder_folders(self, user_id: int, folder_ids: List[int]) -> List[dict]:
        folders = (
            self.db.query(ChatFolder)
            .filter(ChatFolder.user_id == user_id)
            .order_by(ChatFolder.position.asc(), ChatFolder.id.asc())
            .all()
        )
        by_id = {f.id: f for f in folders}
        ordered: List[ChatFolder] = []
        seen: set[int] = set()
        for fid in folder_ids:
            folder = by_id.get(fid)
            if folder is None or fid in seen:
                continue
            seen.add(fid)
            ordered.append(folder)
        for folder in folders:
            if folder.id not in seen:
                ordered.append(folder)
        for pos, folder in enumerate(ordered):
            folder.position = pos
        self.db.flush()
        return [self._folder_payload(f) for f in ordered]

    def share_folder(self, user_id: int, folder_id: int) -> dict:
        if not self._has_feature(user_id, "folder_share"):
            raise ValueError("folder_share_required")
        folder = (
            self.db.query(ChatFolder)
            .filter(ChatFolder.id == folder_id, ChatFolder.user_id == user_id)
            .first()
        )
        if not folder:
            raise ValueError("folder_not_found")
        row = (
            self.db.query(ChatFolderShare)
            .filter(
                ChatFolderShare.folder_id == folder.id,
                ChatFolderShare.revoked_at.is_(None),
            )
            .first()
        )
        if row is None:
            row = ChatFolderShare(
                token=secrets.token_urlsafe(16),
                folder_id=folder.id,
                owner_user_id=user_id,
            )
            self.db.add(row)
            self.db.flush()
        return {"token": row.token, "name": folder.name}

    def import_shared_folder(self, user_id: int, token: str) -> dict:
        if not self._has_feature(user_id, "folder_share"):
            raise ValueError("folder_share_required")
        key = (token or "").strip()
        if not key:
            raise ValueError("folder_share_not_found")
        row = (
            self.db.query(ChatFolderShare)
            .filter(
                ChatFolderShare.token == key,
                ChatFolderShare.revoked_at.is_(None),
            )
            .first()
        )
        if not row:
            raise ValueError("folder_share_not_found")
        source = (
            self.db.query(ChatFolder)
            .filter(ChatFolder.id == row.folder_id)
            .first()
        )
        if not source:
            raise ValueError("folder_share_not_found")
        payload = self._folder_payload(source)
        name = self._folder_text_for_importer(user_id, payload.get("name"))
        icon = self._folder_text_for_importer(user_id, payload.get("icon"))
        return self.create_folder(
            user_id,
            name or payload["name"],
            icon,
            payload.get("conversation_ids") or [],
            payload.get("channel_ids") or [],
            payload.get("filters") or {},
        )

    def _folder_text_for_importer(
        self, user_id: int, raw: Optional[str]
    ) -> Optional[str]:
        """Keep tokens if the importer may send them; otherwise preview.

        Import is receiving someone else's folder title/icon — do not 403
        a user who only has folder_share (57) and not custom_emoji (69).
        """
        from app.services.emoji_pack_service import (
            EmojiPackService,
            preview_text_with_custom_emoji,
        )

        text = raw
        if not (text or "").strip():
            return text
        try:
            EmojiPackService(self.db).require_send_tokens(user_id, text)
        except ValueError:
            return preview_text_with_custom_emoji(text)
        return text
