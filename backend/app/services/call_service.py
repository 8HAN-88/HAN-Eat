"""1:1 voice/video call lifecycle + SSE signaling relay."""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Optional

from fastapi import HTTPException, status
from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from app.models.call import CallSession
from app.models.conversation import Conversation, ConversationMember
from app.models.user import User
from app.models.user_block import UserBlock
from app.services.notification_service import NotificationService
from app.services.user_event_bus import publish_user_event

RING_TIMEOUT_SECONDS = 60
ACTIVE_STATUSES = ("ringing", "active")


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

    def _expire_if_needed(self, call: CallSession) -> CallSession:
        if call.status != "ringing":
            return call
        created = call.created_at or datetime.utcnow()
        if created + timedelta(seconds=RING_TIMEOUT_SECONDS) <= datetime.utcnow():
            call.status = "missed"
            call.ended_at = datetime.utcnow()
            self.db.flush()
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

        caller = self.db.query(User).filter(User.id == caller_id).first()
        caller_name = (caller.name if caller else None) or "Звонок"
        self._publish(
            callee_id,
            "call.invite",
            call,
            {
                "from_user_id": caller_id,
                "from_name": caller_name,
                "from_avatar_url": getattr(caller, "avatar_url", None) if caller else None,
            },
        )
        # Offline ring via FCM (same path as chat messages).
        try:
            NotificationService(self.db).create_notification(
                user_id=callee_id,
                type="call.incoming",
                title=caller_name,
                body="Входящий видеозвонок" if media_norm == "video" else "Входящий звонок",
                entity_type="call",
                entity_id=call.id,
                actor_id=caller_id,
                data={
                    "type": "call.incoming",
                    "route": "call",
                    "call_id": call.id,
                    "conversation_id": conversation_id,
                    "media": media_norm,
                    "caller_id": caller_id,
                    "caller_name": caller_name,
                },
            )
        except Exception:
            pass
        return call

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
