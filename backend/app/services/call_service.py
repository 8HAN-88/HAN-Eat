"""1:1 voice/video call lifecycle + SSE signaling relay."""
from __future__ import annotations

import json
from datetime import datetime, timedelta
from typing import Any, Optional

from fastapi import HTTPException, status
from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.call import CallParticipant, CallSession
from app.models.conversation import Conversation, ConversationMember, Message
from app.models.user import User
from app.models.user_block import UserBlock
from app.services.chat_event_bus import publish as publish_chat_event
from app.services.notification_service import NotificationService
from app.services.user_event_bus import publish_user_event

ACTIVE_STATUSES = ("ringing", "active")
MAX_GROUP_CALL_PARTICIPANTS = 4
PARTICIPANT_LIVE = ("invited", "ringing", "joined")
WEBRTC_SIGNAL_KINDS = ("offer", "answer", "ice", "renegotiate")
# Control signals may broadcast to all joined peers when to_user_id is omitted.
CONTROL_SIGNAL_KINDS = ("mute", "camera")
ALL_SIGNAL_KINDS = WEBRTC_SIGNAL_KINDS + CONTROL_SIGNAL_KINDS


def ring_timeout_seconds() -> int:
    return max(15, int(getattr(settings, "CALL_RING_TIMEOUT_SECONDS", 60) or 60))


class CallService:
    def __init__(self, db: Session):
        self.db = db

    def _get_call(self, call_id: int, *, for_update: bool = False) -> CallSession:
        q = self.db.query(CallSession).filter(CallSession.id == call_id)
        if for_update:
            q = q.with_for_update()
        call = q.first()
        if not call:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Call not found")
        return call

    def _assert_participant(self, call: CallSession, user_id: int) -> None:
        if getattr(call, "kind", "direct") == "group":
            row = (
                self.db.query(CallParticipant.id)
                .filter(
                    CallParticipant.call_id == call.id,
                    CallParticipant.user_id == user_id,
                    CallParticipant.status.in_(PARTICIPANT_LIVE + ("left", "rejected", "missed")),
                )
                .first()
            )
            if not row and user_id != call.caller_id:
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")
            return
        if user_id not in (call.caller_id, call.callee_id):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    def _peer_id(self, call: CallSession, user_id: int) -> int:
        if call.callee_id is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Peer signaling requires to_user_id"
            )
        return call.callee_id if user_id == call.caller_id else call.caller_id

    def _is_group(self, call: CallSession) -> bool:
        return (getattr(call, "kind", None) or "direct") == "group"

    def _participant_ids(self, call_id: int, *, live_only: bool = True) -> list[int]:
        q = self.db.query(CallParticipant.user_id).filter(CallParticipant.call_id == call_id)
        if live_only:
            q = q.filter(CallParticipant.status.in_(("invited", "ringing", "joined")))
        return [uid for (uid,) in q.all()]

    def _has_block(self, a: int, b: int) -> bool:
        return (
            self.db.query(UserBlock.id)
            .filter(
                or_(
                    and_(
                        UserBlock.blocker_user_id == a,
                        UserBlock.blocked_user_id == b,
                    ),
                    and_(
                        UserBlock.blocker_user_id == b,
                        UserBlock.blocked_user_id == a,
                    ),
                )
            )
            .first()
            is not None
        )

    def _user_busy(self, user_id: int, *, exclude_call_id: Optional[int] = None) -> bool:
        q = self.db.query(CallSession.id).filter(
            CallSession.status.in_(ACTIVE_STATUSES),
            (CallSession.caller_id == user_id) | (CallSession.callee_id == user_id),
        )
        if exclude_call_id is not None:
            q = q.filter(CallSession.id != exclude_call_id)
        if q.first() is not None:
            return True
        pq = (
            self.db.query(CallParticipant.id)
            .join(CallSession, CallSession.id == CallParticipant.call_id)
            .filter(
                CallParticipant.user_id == user_id,
                CallParticipant.status.in_(("ringing", "joined")),
                CallSession.status.in_(ACTIVE_STATUSES),
            )
        )
        if exclude_call_id is not None:
            pq = pq.filter(CallParticipant.call_id != exclude_call_id)
        return pq.first() is not None

    def _duration_sec(self, call: CallSession) -> int:
        if not call.started_at or not call.ended_at:
            return 0
        delta = call.ended_at - call.started_at
        return max(0, int(delta.total_seconds()))

    def _append_call_message(self, call: CallSession) -> Optional[Message]:
        """Insert a chat history row for a terminal call (missed/rejected/etc)."""
        if call.status not in ("ended", "rejected", "missed", "cancelled"):
            return None
        # Idempotent: one history bubble per call.
        existing = (
            self.db.query(Message.id)
            .filter(
                Message.conversation_id == call.conversation_id,
                Message.type == "call",
                Message.content.like(f'%"call_id": {call.id}%'),
            )
            .first()
        )
        if existing:
            return None
        payload = {
            "call_id": call.id,
            "media": call.media,
            "kind": getattr(call, "kind", None) or "direct",
            "status": call.status,
            "duration_sec": self._duration_sec(call),
            "caller_id": call.caller_id,
            "callee_id": call.callee_id,
            "ended_by_user_id": call.ended_by_user_id,
        }
        msg = Message(
            conversation_id=call.conversation_id,
            sender_id=call.caller_id,
            type="call",
            content=json.dumps(payload, ensure_ascii=False),
        )
        self.db.add(msg)
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == call.conversation_id)
            .first()
        )
        if conv:
            conv.updated_at = datetime.utcnow()
        self.db.flush()
        setattr(call, "_history_message", msg)
        return msg

    @staticmethod
    def publish_history_events(db: Session, call: CallSession) -> None:
        msg = getattr(call, "_history_message", None)
        if msg is None:
            return
        payload = {
            "id": msg.id,
            "conversation_id": msg.conversation_id,
            "sender_id": msg.sender_id,
            "type": msg.type,
            "content": msg.content,
            "media_url": None,
            "reply_to_message_id": None,
            "forward_from_user_id": None,
            "forward_from_name": None,
            "forwarded_from_message_id": None,
            "forwarded_from_conversation_id": None,
            "inline_keyboard": None,
            "created_at": msg.created_at.isoformat() if msg.created_at else None,
            "edited_at": None,
            "disable_webpage_preview": False,
            "media_group_id": None,
            "is_paid": False,
            "price_stars": 0,
            "purchased": True,
            "reactions": [],
        }
        publish_chat_event(
            msg.conversation_id,
            {"type": "message.new", "message": payload},
        )
        member_ids = (
            db.query(ConversationMember.user_id)
            .filter(ConversationMember.conversation_id == msg.conversation_id)
            .all()
        )
        for (uid,) in member_ids:
            publish_user_event(
                uid,
                {"event": "chat.inbox", "conversation_id": msg.conversation_id},
            )

    def _expire_if_needed(self, call: CallSession) -> CallSession:
        if call.status != "ringing":
            return call
        created = call.created_at or datetime.utcnow()
        if created + timedelta(seconds=ring_timeout_seconds()) <= datetime.utcnow():
            call.status = "missed"
            call.ended_at = datetime.utcnow()
            self.db.flush()
            self._append_call_message(call)
            self._publish_both(call, "call.ended", {"reason": "missed"})
        return call

    def _call_payload(self, call: CallSession, extra: Optional[dict] = None) -> dict:
        payload = {
            "event": "call",
            "call_id": call.id,
            "conversation_id": call.conversation_id,
            "caller_id": call.caller_id,
            "callee_id": call.callee_id,
            "call_kind": getattr(call, "kind", None) or "direct",
            "media": call.media,
            "status": call.status,
            "started_at": call.started_at.isoformat() if call.started_at else None,
            "ended_at": call.ended_at.isoformat() if call.ended_at else None,
            "created_at": call.created_at.isoformat() if call.created_at else None,
            "ring_timeout_seconds": ring_timeout_seconds(),
        }
        if extra:
            payload.update(extra)
        return payload

    def _voip_end_user(self, user_id: int, call: CallSession) -> None:
        """Dismiss CallKit UI on iOS when the call ends before/while ringing."""
        try:
            from app.services.voip_push_service import get_voip_push_service, voip_push_configured

            if not voip_push_configured():
                return
            user = self.db.query(User).filter(User.id == user_id).first()
            if not user or not getattr(user, "voip_token", None):
                return
            get_voip_push_service().send_end(
                self.db, user, call_id=call.id, media=call.media or "voice"
            )
        except Exception:
            pass

    def _publish(self, user_id: int, event: str, call: CallSession, extra: Optional[dict] = None) -> None:
        body = self._call_payload(call, extra)
        body["event"] = event
        publish_user_event(user_id, body)
        if event in ("call.ended", "call.cancelled", "call.rejected"):
            self._voip_end_user(user_id, call)

    def _publish_both(self, call: CallSession, event: str, extra: Optional[dict] = None) -> None:
        if self._is_group(call):
            for uid in set(self._participant_ids(call.id, live_only=False) + [call.caller_id]):
                self._publish(uid, event, call, extra)
            return
        self._publish(call.caller_id, event, call, extra)
        if call.callee_id is not None:
            self._publish(call.callee_id, event, call, extra)

    @staticmethod
    def ice_servers() -> list[dict[str, Any]]:
        servers: list[dict[str, Any]] = []
        stun_raw = (getattr(settings, "WEBRTC_STUN_URLS", "") or "").strip()
        for url in [u.strip() for u in stun_raw.split(",") if u.strip()]:
            servers.append({"urls": url})
        turn_raw = (getattr(settings, "WEBRTC_TURN_URLS", "") or "").strip()
        turn_urls = [u.strip() for u in turn_raw.split(",") if u.strip()]
        if turn_urls:
            entry: dict[str, Any] = {"urls": turn_urls if len(turn_urls) > 1 else turn_urls[0]}
            user = (getattr(settings, "WEBRTC_TURN_USERNAME", "") or "").strip()
            cred = (getattr(settings, "WEBRTC_TURN_CREDENTIAL", "") or "").strip()
            if user:
                entry["username"] = user
            if cred:
                entry["credential"] = cred
            servers.append(entry)
        if not servers:
            servers = [
                {"urls": "stun:stun.l.google.com:19302"},
                {"urls": "stun:stun1.l.google.com:19302"},
            ]
        return servers

    def create_call(
        self,
        caller_id: int,
        *,
        conversation_id: int,
        media: str = "voice",
    ) -> CallSession:
        media_norm = (media or "voice").strip().lower()
        if media_norm not in ("voice", "video"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="media must be voice or video"
            )
        member = (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == caller_id,
            )
            .first()
        )
        if not member:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id)
            .first()
        )
        if not conv:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Chat not found")
        if conv.type == "group":
            return self.create_group_call(
                caller_id, conversation_id=conversation_id, media=media_norm
            )
        if conv.type != "direct":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Calls only supported in direct chats"
            )
        callee_id = (
            conv.direct_user_high_id
            if conv.direct_user_low_id == caller_id
            else conv.direct_user_low_id
        )
        if not callee_id or callee_id == caller_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Call peer not found"
            )
        callee = (
            self.db.query(User)
            .filter(User.id == callee_id, User.deleted_at.is_(None))
            .first()
        )
        if not callee or bool(getattr(callee, "is_bot", False)):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot call this user"
            )
        if self._has_block(caller_id, callee_id):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="User is blocked")
        from app.services.call_privacy import can_call_user

        if not can_call_user(self.db, caller_id, callee):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="call_privacy_denied",
            )
        if self._user_busy(caller_id) or self._user_busy(callee_id):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={"code": "USER_BUSY", "message": "Пользователь занят"},
            )

        call = CallSession(
            conversation_id=conversation_id,
            caller_id=caller_id,
            callee_id=callee_id,
            kind="direct",
            media=media_norm,
            status="ringing",
        )
        self.db.add(call)
        self.db.flush()
        # Invite/push happens AFTER commit in the API (avoid GET 404 race).
        return call

    def notify_incoming(self, call: CallSession) -> None:
        """Publish SSE invite + ephemeral FCM after the call row is committed."""
        from app.services.emoji_pack_service import display_name_or_default

        caller = self.db.query(User).filter(User.id == call.caller_id).first()
        caller_name = display_name_or_default(
            caller.name if caller else None,
            default="Звонок",
        )
        self._publish(
            call.callee_id,
            "call.invite",
            call,
            {
                "from_user_id": call.caller_id,
                "from_name": caller_name,
                "from_avatar_url": getattr(caller, "avatar_url", None) if caller else None,
            },
        )
        try:
            NotificationService(self.db).create_notification(
                user_id=call.callee_id,
                type="call.incoming",
                title=caller_name,
                body="Входящий видеозвонок" if call.media == "video" else "Входящий звонок",
                entity_type="call",
                entity_id=call.id,
                actor_id=call.caller_id,
                data={
                    "type": "call.incoming",
                    "route": "call",
                    "call_id": call.id,
                    "conversation_id": call.conversation_id,
                    "media": call.media,
                    "call_kind": "direct",
                    "caller_id": call.caller_id,
                    "caller_name": caller_name,
                    "caller_avatar": getattr(caller, "avatar_url", None) or "",
                },
                persist=False,
            )
        except Exception:
            pass

    def answer_call(self, user_id: int, call_id: int) -> CallSession:
        call = self._get_call(call_id, for_update=True)
        self._expire_if_needed(call)
        if self._is_group(call):
            return self.join_group_call(user_id, call_id)
        self._assert_participant(call, user_id)
        if user_id != call.callee_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN, detail="Only callee can answer"
            )
        if call.status != "ringing":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Call is not ringing"
            )
        if self._user_busy(user_id, exclude_call_id=call.id):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={"code": "USER_BUSY", "message": "Пользователь занят"},
            )
        call.status = "active"
        call.started_at = datetime.utcnow()
        self.db.flush()
        self._publish_both(call, "call.answered")
        return call

    def reject_call(self, user_id: int, call_id: int) -> CallSession:
        call = self._get_call(call_id, for_update=True)
        self._expire_if_needed(call)
        if self._is_group(call):
            return self.leave_group_call(user_id, call_id, end_for_all=False)
        self._assert_participant(call, user_id)
        if user_id != call.callee_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN, detail="Only callee can reject"
            )
        if call.status != "ringing":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Call is not ringing"
            )
        call.status = "rejected"
        call.ended_at = datetime.utcnow()
        call.ended_by_user_id = user_id
        self.db.flush()
        self._append_call_message(call)
        self._publish_both(call, "call.rejected")
        return call

    def cancel_call(self, user_id: int, call_id: int) -> CallSession:
        call = self._get_call(call_id, for_update=True)
        self._expire_if_needed(call)
        self._assert_participant(call, user_id)
        if user_id != call.caller_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN, detail="Only caller can cancel"
            )
        if call.status != "ringing":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Call is not ringing"
            )
        call.status = "cancelled"
        call.ended_at = datetime.utcnow()
        call.ended_by_user_id = user_id
        self.db.flush()
        self._append_call_message(call)
        self._publish_both(call, "call.cancelled")
        return call

    def end_call(self, user_id: int, call_id: int) -> CallSession:
        call = self._get_call(call_id, for_update=True)
        self._expire_if_needed(call)
        self._assert_participant(call, user_id)
        if call.status in ("ended", "rejected", "missed", "cancelled"):
            return call
        if self._is_group(call):
            return self.leave_group_call(user_id, call_id, end_for_all=(user_id == call.caller_id))
        if call.status == "ringing":
            # Treat hangup during ring as cancel/reject depending on role.
            if user_id == call.caller_id:
                return self.cancel_call(user_id, call_id)
            return self.reject_call(user_id, call_id)
        call.status = "ended"
        call.ended_at = datetime.utcnow()
        call.ended_by_user_id = user_id
        self.db.flush()
        self._append_call_message(call)
        self._publish_both(call, "call.ended", {"reason": "hangup", "ended_by": user_id})
        return call

    def relay_signal(
        self,
        user_id: int,
        call_id: int,
        *,
        kind: str,
        payload: dict[str, Any],
        to_user_id: Optional[int] = None,
    ) -> CallSession:
        call = self._get_call(call_id, for_update=True)
        self._expire_if_needed(call)
        self._assert_participant(call, user_id)
        if call.status not in ("ringing", "active"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Call is not active"
            )
        kind_norm = (kind or "").strip().lower()
        if kind_norm not in ALL_SIGNAL_KINDS:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid signal kind"
            )
        if not isinstance(payload, dict):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="payload must be an object"
            )
        is_control = kind_norm in CONTROL_SIGNAL_KINDS
        targets: list[int] = []
        if self._is_group(call):
            if to_user_id:
                if to_user_id == user_id:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot signal self"
                    )
                self._assert_participant(call, to_user_id)
                targets = [to_user_id]
            elif is_control:
                # Fan-out media state to already-joined peers only.
                joined = (
                    self.db.query(CallParticipant.user_id)
                    .filter(
                        CallParticipant.call_id == call.id,
                        CallParticipant.status == "joined",
                        CallParticipant.user_id != user_id,
                    )
                    .all()
                )
                targets = [uid for (uid,) in joined]
            else:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="to_user_id required for group call signaling",
                )
        else:
            targets = [self._peer_id(call, user_id)]

        for peer_id in targets:
            self._publish(
                peer_id,
                "call.signal",
                call,
                {
                    "from_user_id": user_id,
                    "to_user_id": peer_id,
                    "kind": kind_norm,
                    "payload": payload,
                },
            )
        return call

    def get_call_for_user(self, user_id: int, call_id: int) -> CallSession:
        call = self._get_call(call_id)
        self._expire_if_needed(call)
        self._assert_participant(call, user_id)
        return call

    def create_group_call(
        self,
        host_id: int,
        *,
        conversation_id: int,
        media: str = "voice",
    ) -> CallSession:
        media_norm = (media or "voice").strip().lower()
        if media_norm not in ("voice", "video"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="media must be voice or video"
            )
        members = (
            self.db.query(ConversationMember.user_id)
            .filter(ConversationMember.conversation_id == conversation_id)
            .all()
        )
        member_ids = [uid for (uid,) in members]
        if host_id not in member_ids:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")
        from app.services.chat_service import ChatService

        if not ChatService(self.db).can_manage_group_video_chats(
            conversation_id, host_id
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={
                    "code": "GROUP_CALL_FORBIDDEN",
                    "message": "Нет права управлять групповыми звонками",
                },
            )
        # Host + up to MAX-1 others (invite first N by membership order).
        others = [uid for uid in member_ids if uid != host_id][: MAX_GROUP_CALL_PARTICIPANTS - 1]
        if not others:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Group has no other members"
            )
        if self._user_busy(host_id):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={"code": "USER_BUSY", "message": "Вы уже в звонке"},
            )
        call = CallSession(
            conversation_id=conversation_id,
            caller_id=host_id,
            callee_id=None,
            kind="group",
            media=media_norm,
            status="active",
            started_at=datetime.utcnow(),
        )
        self.db.add(call)
        self.db.flush()
        self.db.add(
            CallParticipant(
                call_id=call.id,
                user_id=host_id,
                status="joined",
                joined_at=datetime.utcnow(),
            )
        )
        for uid in others:
            self.db.add(
                CallParticipant(
                    call_id=call.id,
                    user_id=uid,
                    status="ringing",
                )
            )
        self.db.flush()
        setattr(call, "_invite_user_ids", others)
        return call

    def notify_group_incoming(self, call: CallSession) -> None:
        invite_ids = getattr(call, "_invite_user_ids", None) or [
            uid
            for uid in self._participant_ids(call.id, live_only=True)
            if uid != call.caller_id
        ]
        from app.services.emoji_pack_service import display_name_or_default

        host = self.db.query(User).filter(User.id == call.caller_id).first()
        host_name = display_name_or_default(
            host.name if host else None,
            default="Групповой звонок",
        )
        for uid in invite_ids:
            self._publish(
                uid,
                "call.invite",
                call,
                {
                    "from_user_id": call.caller_id,
                    "from_name": host_name,
                    "from_avatar_url": getattr(host, "avatar_url", None) if host else None,
                },
            )
            try:
                NotificationService(self.db).create_notification(
                    user_id=uid,
                    type="call.incoming",
                    title=host_name,
                    body="Групповой видеозвонок" if call.media == "video" else "Групповой звонок",
                    entity_type="call",
                    entity_id=call.id,
                    actor_id=call.caller_id,
                    data={
                        "type": "call.incoming",
                        "route": "call",
                        "call_id": call.id,
                        "conversation_id": call.conversation_id,
                        "media": call.media,
                        "call_kind": "group",
                        "caller_id": call.caller_id,
                        "caller_name": host_name,
                    },
                    persist=False,
                )
            except Exception:
                pass

    def join_group_call(self, user_id: int, call_id: int) -> CallSession:
        call = self._get_call(call_id, for_update=True)
        if not self._is_group(call):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Not a group call")
        if call.status not in ("ringing", "active"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Call is not active"
            )
        row = (
            self.db.query(CallParticipant)
            .filter(CallParticipant.call_id == call.id, CallParticipant.user_id == user_id)
            .with_for_update()
            .first()
        )
        if not row:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")
        if row.status == "joined":
            return call
        joined_count = (
            self.db.query(CallParticipant.id)
            .filter(CallParticipant.call_id == call.id, CallParticipant.status == "joined")
            .count()
        )
        if joined_count >= MAX_GROUP_CALL_PARTICIPANTS:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={"code": "CALL_FULL", "message": "Звонок заполнен"},
            )
        if self._user_busy(user_id, exclude_call_id=call.id):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={"code": "USER_BUSY", "message": "Вы уже в звонке"},
            )
        row.status = "joined"
        row.joined_at = datetime.utcnow()
        row.left_at = None
        if call.status == "ringing":
            call.status = "active"
            call.started_at = call.started_at or datetime.utcnow()
        self.db.flush()
        already = [
            uid
            for uid in self._participant_ids(call.id, live_only=True)
            if uid != user_id
        ]
        joined_peers = (
            self.db.query(CallParticipant.user_id)
            .filter(
                CallParticipant.call_id == call.id,
                CallParticipant.status == "joined",
                CallParticipant.user_id != user_id,
            )
            .all()
        )
        peer_ids = [uid for (uid,) in joined_peers]
        for uid in set(already + peer_ids + [call.caller_id]):
            self._publish(
                uid,
                "call.participant_joined",
                call,
                {"user_id": user_id, "joined_user_ids": peer_ids},
            )
        self._publish(
            user_id,
            "call.answered",
            call,
            {"joined_user_ids": peer_ids},
        )
        return call

    def leave_group_call(
        self, user_id: int, call_id: int, *, end_for_all: bool = False
    ) -> CallSession:
        call = self._get_call(call_id, for_update=True)
        if not self._is_group(call):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Not a group call")
        row = (
            self.db.query(CallParticipant)
            .filter(CallParticipant.call_id == call.id, CallParticipant.user_id == user_id)
            .with_for_update()
            .first()
        )
        if row and row.status != "left":
            if row.status == "ringing":
                row.status = "rejected"
            else:
                row.status = "left"
            row.left_at = datetime.utcnow()
            self.db.flush()

        if end_for_all or user_id == call.caller_id:
            call.status = "ended"
            call.ended_at = datetime.utcnow()
            call.ended_by_user_id = user_id
            for p in (
                self.db.query(CallParticipant)
                .filter(
                    CallParticipant.call_id == call.id,
                    CallParticipant.status.in_(("invited", "ringing", "joined")),
                )
                .all()
            ):
                if p.status == "ringing":
                    p.status = "missed"
                elif p.status == "joined":
                    p.status = "left"
                p.left_at = p.left_at or datetime.utcnow()
            self.db.flush()
            self._append_call_message(call)
            self._publish_both(call, "call.ended", {"reason": "hangup", "ended_by": user_id})
            return call

        still = (
            self.db.query(CallParticipant.id)
            .filter(CallParticipant.call_id == call.id, CallParticipant.status == "joined")
            .count()
        )
        self._publish_both(
            call,
            "call.participant_left",
            {"user_id": user_id, "joined_count": still},
        )
        if still == 0:
            call.status = "ended"
            call.ended_at = datetime.utcnow()
            call.ended_by_user_id = user_id
            self.db.flush()
            self._append_call_message(call)
            self._publish_both(call, "call.ended", {"reason": "empty"})
        return call

    def invite_to_group_call(
        self, actor_id: int, call_id: int, invitee_id: int
    ) -> CallSession:
        """Invite another group member into an active group call (mid-call)."""
        call = self._get_call(call_id, for_update=True)
        if not self._is_group(call):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Not a group call")
        if call.status != "active":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Call is not active"
            )
        actor = (
            self.db.query(CallParticipant)
            .filter(
                CallParticipant.call_id == call.id,
                CallParticipant.user_id == actor_id,
                CallParticipant.status == "joined",
            )
            .first()
        )
        if not actor:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN, detail="Only joined participants can invite"
            )
        if invitee_id == actor_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot invite yourself"
            )
        member = (
            self.db.query(ConversationMember.id)
            .filter(
                ConversationMember.conversation_id == call.conversation_id,
                ConversationMember.user_id == invitee_id,
            )
            .first()
        )
        if not member:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="User is not in this group"
            )
        invitee = (
            self.db.query(User)
            .filter(User.id == invitee_id, User.deleted_at.is_(None))
            .first()
        )
        if not invitee or bool(getattr(invitee, "is_bot", False)):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot invite this user"
            )

        row = (
            self.db.query(CallParticipant)
            .filter(CallParticipant.call_id == call.id, CallParticipant.user_id == invitee_id)
            .with_for_update()
            .first()
        )
        if row and row.status == "joined":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="User is already in the call"
            )

        live_count = (
            self.db.query(CallParticipant.id)
            .filter(
                CallParticipant.call_id == call.id,
                CallParticipant.status.in_(("joined", "ringing")),
            )
            .count()
        )
        # Re-invite of an already-ringing user does not consume an extra seat.
        if not (row and row.status == "ringing") and live_count >= MAX_GROUP_CALL_PARTICIPANTS:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={"code": "CALL_FULL", "message": "Звонок заполнен"},
            )
        if self._user_busy(invitee_id, exclude_call_id=call.id):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={"code": "USER_BUSY", "message": "Пользователь занят"},
            )

        if row:
            row.status = "ringing"
            row.joined_at = None
            row.left_at = None
        else:
            self.db.add(
                CallParticipant(
                    call_id=call.id,
                    user_id=invitee_id,
                    status="ringing",
                )
            )
        self.db.flush()
        setattr(call, "_invite_user_ids", [invitee_id])
        for uid in self._participant_ids(call.id, live_only=True):
            if uid == invitee_id:
                continue
            self._publish(
                uid,
                "call.participant_invited",
                call,
                {"user_id": invitee_id, "invited_by": actor_id},
            )
        return call

    def list_participants(self, user_id: int, call_id: int) -> list[dict[str, Any]]:
        call = self.get_call_for_user(user_id, call_id)
        rows = (
            self.db.query(CallParticipant, User)
            .join(User, User.id == CallParticipant.user_id)
            .filter(CallParticipant.call_id == call.id)
            .all()
        )
        out = []
        for part, user in rows:
            out.append(
                {
                    "user_id": user.id,
                    "name": user.name,
                    "avatar_url": getattr(user, "avatar_url", None),
                    "status": part.status,
                    "is_host": user.id == call.caller_id,
                    "joined_at": part.joined_at.isoformat() if part.joined_at else None,
                }
            )
        return out

    @classmethod
    def expire_stale_rings(cls, db: Session) -> list[CallSession]:
        """Mark unanswered ringing calls / group invites as missed (maintenance loop)."""
        cutoff = datetime.utcnow() - timedelta(seconds=ring_timeout_seconds())
        rows = (
            db.query(CallSession)
            .filter(CallSession.status == "ringing", CallSession.created_at <= cutoff)
            .all()
        )
        svc = cls(db)
        expired: list[CallSession] = []
        for call in rows:
            call.status = "missed"
            call.ended_at = datetime.utcnow()
            db.flush()
            svc._append_call_message(call)
            svc._publish_both(call, "call.ended", {"reason": "missed"})
            expired.append(call)

        # Group calls start as active for the host; expire unanswered invitees separately.
        stale_invites = (
            db.query(CallParticipant, CallSession)
            .join(CallSession, CallSession.id == CallParticipant.call_id)
            .filter(
                CallSession.kind == "group",
                CallSession.status == "active",
                CallParticipant.status == "ringing",
                CallSession.created_at <= cutoff,
            )
            .all()
        )
        for part, call in stale_invites:
            part.status = "missed"
            part.left_at = datetime.utcnow()
            db.flush()
            svc._publish(part.user_id, "call.ended", call, {"reason": "missed"})
        return expired
