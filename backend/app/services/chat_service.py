"""Сервис личных чатов и контактов."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

from sqlalchemy import and_, func, or_
from sqlalchemy.orm import Session, joinedload

from app.models.conversation import (
    Contact,
    Conversation,
    ConversationMember,
    Message,
    MessageReaction,
)
from app.models.chat_folder import ChatFolder, ChatFolderItem
from app.models.user import User
from app.models.user_block import UserBlock
from app.services.notification_service import NotificationService


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
        self._get_user_or_404(peer_user_id)
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

    def list_members(self, conversation_id: int, user_id: int) -> List[User]:
        if not self._is_member(conversation_id, user_id):
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
        return [by_id[i] for i in ids if i in by_id]

    def create_group(
        self, creator_id: int, title: str, member_ids: List[int]
    ) -> Conversation:
        clean_title = title.strip()
        if not clean_title:
            raise ValueError("empty_title")
        others = {uid for uid in member_ids if uid != creator_id}
        if not others:
            raise ValueError("need_members")
        for uid in others:
            self._get_user_or_404(uid)
            if self.has_block_between(creator_id, uid):
                raise ValueError("user_blocked")

        conv = Conversation(
            type="group",
            title=clean_title[:120],
            created_by_user_id=creator_id,
        )
        self.db.add(conv)
        self.db.flush()
        all_ids = others | {creator_id}
        for uid in all_ids:
            self.db.add(
                ConversationMember(conversation_id=conv.id, user_id=uid)
            )
        self.db.flush()
        return conv

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

    def group_all_read(
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
            m.last_read_message_id is not None
            and m.last_read_message_id >= message_id
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

        last_msg_subq = (
            self.db.query(
                Message.conversation_id.label("conversation_id"),
                func.max(Message.id).label("max_id"),
            )
            .filter(
                Message.conversation_id.in_(conv_ids),
                Message.deleted_at.is_(None),
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
                or_(
                    ConversationMember.last_read_message_id.is_(None),
                    Message.id > ConversationMember.last_read_message_id,
                ),
            )
            .group_by(Message.conversation_id)
            .all()
        )
        unread_map = {row.conversation_id: row.cnt for row in unread_rows}

        results = []
        for conv in convs:
            member = member_map[conv.id]
            is_archived = member.archived_at is not None
            if archived_only and not is_archived:
                continue
            if not archived_only and is_archived:
                continue
            last_msg = last_messages.get(conv.id)
            unread = unread_map.get(conv.id, 0)

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
                    "pinned": member.pinned,
                    "archived": is_archived,
                    "muted": member.muted_at is not None,
                    "member_count": member_count,
                    "members_preview": members_preview,
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
        last_msg = (
            self.db.query(Message)
            .filter(
                Message.conversation_id == conv.id,
                Message.deleted_at.is_(None),
            )
            .order_by(Message.id.desc())
            .first()
        )
        unread_q = self.db.query(func.count(Message.id)).filter(
            Message.conversation_id == conv.id,
            Message.sender_id != user_id,
            Message.deleted_at.is_(None),
        )
        if member.last_read_message_id:
            unread_q = unread_q.filter(Message.id > member.last_read_message_id)
        unread = unread_q.scalar() or 0
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
        return {
            "conversation": conv,
            "peer": peer,
            "last_message": last_msg,
            "unread_count": unread,
            "pinned": member.pinned,
            "archived": member.archived_at is not None,
            "muted": member.muted_at is not None,
            "member_count": member_count,
            "members_preview": members_preview,
        }

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
        member.pinned = pinned

    def set_muted(self, conversation_id: int, user_id: int, muted: bool) -> None:
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
        member.muted_at = (
            datetime.now(timezone.utc).replace(tzinfo=None) if muted else None
        )

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
        clean = title.strip()
        if not clean:
            raise ValueError("empty_title")
        conv.title = clean[:120]
        conv.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        return conv

    def add_group_members(
        self, conversation_id: int, actor_id: int, user_ids: List[int]
    ) -> int:
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        self._get_group_or_error(conversation_id)
        added = 0
        for uid in user_ids:
            if uid == actor_id:
                continue
            if self._is_member(conversation_id, uid):
                continue
            self._get_user_or_404(uid)
            if self.has_block_between(actor_id, uid):
                raise ValueError("user_blocked")
            self.db.add(
                ConversationMember(conversation_id=conversation_id, user_id=uid)
            )
            added += 1
        return added

    def remove_group_member(
        self, conversation_id: int, actor_id: int, target_user_id: int
    ) -> None:
        if not self._is_member(conversation_id, actor_id):
            raise ValueError("forbidden")
        conv = self._get_group_or_error(conversation_id)
        if target_user_id != actor_id and conv.created_by_user_id != actor_id:
            raise ValueError("forbidden")
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

    def get_messages(
        self,
        conversation_id: int,
        user_id: int,
        cursor: Optional[int] = None,
        after_id: Optional[int] = None,
        limit: int = 50,
    ) -> Tuple[List[Message], bool]:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")

        if after_id is not None:
            rows = (
                self.db.query(Message)
                .filter(
                    Message.conversation_id == conversation_id,
                    Message.deleted_at.is_(None),
                    Message.id > after_id,
                )
                .order_by(Message.id.asc())
                .limit(limit + 1)
                .all()
            )
            has_more = len(rows) > limit
            if has_more:
                rows = rows[:limit]
            return rows, has_more

        q = (
            self.db.query(Message)
            .filter(
                Message.conversation_id == conversation_id,
                Message.deleted_at.is_(None),
            )
            .order_by(Message.id.desc())
        )
        if cursor:
            q = q.filter(Message.id < cursor)

        rows = q.limit(limit + 1).all()
        has_more = len(rows) > limit
        if has_more:
            rows = rows[:limit]
        rows.reverse()
        return rows, has_more

    def send_message(
        self,
        conversation_id: int,
        sender_id: int,
        msg_type: str,
        content: str,
        media_url: Optional[str] = None,
        reply_to_message_id: Optional[int] = None,
        client_message_id: Optional[str] = None,
    ) -> tuple[Message, bool]:
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
        if msg_type == "poll" and not content.strip():
            raise ValueError("empty_poll")
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

        msg = Message(
            conversation_id=conversation_id,
            sender_id=sender_id,
            type=msg_type,
            content=content.strip() if content else "",
            media_url=media_url,
            reply_to_message_id=reply_to_message_id,
            client_message_id=client_message_id,
        )
        self.db.add(msg)

        if conv:
            conv.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)

        self.db.flush()

        # Уведомление получателю
        members = (
            self.db.query(ConversationMember)
            .filter(ConversationMember.conversation_id == conversation_id)
            .all()
        )
        sender = self.db.query(User).filter(User.id == sender_id).first()
        sender_name = (sender.name or sender.username or "Пользователь") if sender else "Пользователь"
        if msg_type == "voice":
            preview = "🎤 Голосовое"
        elif msg_type == "image":
            preview = "📷 Фото"
        elif msg_type == "file":
            name = content.strip() if content else "Файл"
            preview = f"📎 {name[:80]}"
        elif msg_type == "video":
            preview = "🎬 Видео"
        elif msg_type == "poll":
            from app.services.chat_poll_service import poll_preview_text
            preview = poll_preview_text(content)
        else:
            preview = content[:120] if content else ""
        notif = NotificationService(self.db)
        for m in members:
            if m.user_id == sender_id:
                continue
            if m.muted_at is not None:
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

        return msg, True

    def delete_message(
        self, conversation_id: int, message_id: int, user_id: int
    ) -> None:
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
        if msg.sender_id != user_id:
            raise ValueError("forbidden")
        msg.deleted_at = datetime.now(timezone.utc).replace(tzinfo=None)
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        if conv and conv.pinned_message_id == message_id:
            conv.pinned_message_id = None
            conv.pinned_at = None
            conv.pinned_by_user_id = None

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
        if msg.type != "text":
            raise ValueError("not_editable")
        clean = content.strip()
        if not clean:
            raise ValueError("empty_message")
        msg.content = clean[:4000]
        msg.edited_at = datetime.now(timezone.utc).replace(tzinfo=None)
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        if conv:
            conv.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        return msg

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
                {"emoji": row.emoji, "count": 0, "reacted_by_me": False},
            )
            entry["count"] += 1
            if row.user_id == viewer_id:
                entry["reacted_by_me"] = True
        return {
            mid: list(by_emoji.values())
            for mid, by_emoji in grouped.items()
        }

    def set_message_reaction(
        self, conversation_id: int, message_id: int, user_id: int, emoji: str
    ) -> Optional[str]:
        self._get_active_message(conversation_id, message_id, user_id)
        clean = emoji.strip()
        if not clean or len(clean) > 16:
            raise ValueError("invalid_emoji")
        existing = (
            self.db.query(MessageReaction)
            .filter(
                MessageReaction.message_id == message_id,
                MessageReaction.user_id == user_id,
            )
            .first()
        )
        if existing:
            if existing.emoji == clean:
                self.db.delete(existing)
                return None
            existing.emoji = clean
            return clean
        self.db.add(
            MessageReaction(
                message_id=message_id,
                user_id=user_id,
                emoji=clean,
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
        if not pinned:
            conv.pinned_message_id = None
            conv.pinned_at = None
            conv.pinned_by_user_id = None
            return None
        if message_id is None:
            raise ValueError("missing_message")
        self._get_active_message(conversation_id, message_id, user_id)
        conv.pinned_message_id = message_id
        conv.pinned_at = datetime.now(timezone.utc).replace(tzinfo=None)
        conv.pinned_by_user_id = user_id
        return message_id

    def get_pinned_message(
        self, conversation_id: int, user_id: int
    ) -> Optional[Message]:
        if not self._is_member(conversation_id, user_id):
            raise ValueError("forbidden")
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        if not conv or not conv.pinned_message_id:
            return None
        msg = (
            self.db.query(Message)
            .filter(
                Message.id == conv.pinned_message_id,
                Message.conversation_id == conversation_id,
                Message.deleted_at.is_(None),
            )
            .first()
        )
        if not msg:
            conv.pinned_message_id = None
            conv.pinned_at = None
            conv.pinned_by_user_id = None
            return None
        return msg

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

    def delete_conversation(self, conversation_id: int, user_id: int) -> None:
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
            self.leave_group(conversation_id, user_id)
            return
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
        self.db.delete(member)
        self.db.flush()
        if self._member_count(conversation_id) == 0:
            self.db.delete(conv)

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

    @staticmethod
    def _normalize_filters(filters: Optional[dict]) -> dict:
        if not filters:
            return {}
        return {
            "groups": bool(filters.get("groups")),
            "channels": bool(filters.get("channels")),
            "unread_only": bool(filters.get("unread_only")),
        }

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
        max_pos = (
            self.db.query(func.max(ChatFolder.position))
            .filter(ChatFolder.user_id == user_id)
            .scalar()
        )
        norm_filters = self._normalize_filters(filters)
        folder = ChatFolder(
            user_id=user_id,
            name=name[:64],
            icon=(icon or "")[:8] or None,
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
            folder.icon = icon[:8] if icon else None
        if filters is not None:
            norm_filters = self._normalize_filters(filters)
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
