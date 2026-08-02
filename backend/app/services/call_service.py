"""1:1 voice/video call lifecycle + SSE signaling relay."""
from __future__ import annotations

import json
from datetime import datetime, timedelta
from typing import Any, Optional

from fastapi import HTTPException, status
from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.call import CallSession
from app.models.conversation import Conversation, ConversationMember, Message
from app.models.user import User
from app.models.user_block import UserBlock
from app.services.chat_event_bus import publish as publish_chat_event
from app.services.notification_service import NotificationService
from app.services.user_event_bus import publish_user_event

ACTIVE_STATUSES = ("ringing", "active")


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
        if user_id not in (call.caller_id, call.callee_id):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    def _peer_id(self, call: CallSession, user_id: int) -> int:
        return call.callee_id if user_id == call.caller_id else call.caller_id

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
        return q.first() is not None

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

    def _publish(self, user_id: int, event: str, call: CallSession, extra: Optional[dict] = None) -> None:
        body = self._call_payload(call, extra)
        body["event"] = event
        publish_user_event(user_id, body)

    def _publish_both(self, call: CallSession, event: str, extra: Optional[dict] = None) -> None:
        self._publish(call.caller_id, event, call, extra)
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
        if not conv or conv.type != "direct":
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
        if self._user_busy(caller_id) or self._user_busy(callee_id):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={"code": "USER_BUSY", "message": "Пользователь занят"},
            )

        call = CallSession(
            conversation_id=conversation_id,
            caller_id=caller_id,
            callee_id=callee_id,
            media=media_norm,
            status="ringing",
        )
        self.db.add(call)
        self.db.flush()
        # Invite/push happens AFTER commit in the API (avoid GET 404 race).
        return call

    def notify_incoming(self, call: CallSession) -> None:
        """Publish SSE invite + ephemeral FCM after the call row is committed."""
        caller = self.db.query(User).filter(User.id == call.caller_id).first()
        caller_name = (caller.name if caller else None) or "Звонок"
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
    ) -> CallSession:
        call = self._get_call(call_id, for_update=True)
        self._expire_if_needed(call)
        self._assert_participant(call, user_id)
        if call.status not in ("ringing", "active"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Call is not active"
            )
        kind_norm = (kind or "").strip().lower()
        if kind_norm not in ("offer", "answer", "ice", "renegotiate"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid signal kind"
            )
        if not isinstance(payload, dict):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="payload must be an object"
            )
        peer_id = self._peer_id(call, user_id)
        self._publish(
            peer_id,
            "call.signal",
            call,
            {
                "from_user_id": user_id,
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

    @classmethod
    def expire_stale_rings(cls, db: Session) -> list[CallSession]:
        """Mark unanswered ringing calls as missed (maintenance loop)."""
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
        return expired
