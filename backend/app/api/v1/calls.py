"""1:1 WebRTC call API."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user_required
from app.core.database import get_db
from app.models.user import User
from app.services.call_service import CallService, ring_timeout_seconds

router = APIRouter(prefix="/calls", tags=["Calls"])


class CreateCallRequest(BaseModel):
    conversation_id: int = Field(gt=0)
    media: str = Field(default="voice", pattern="^(voice|video)$")


class CallSignalRequest(BaseModel):
    kind: str = Field(..., min_length=1, max_length=32)
    payload: dict[str, Any] = Field(default_factory=dict)
    to_user_id: Optional[int] = Field(default=None, gt=0)


class InviteCallRequest(BaseModel):
    user_id: int = Field(gt=0)


class IceServersResponse(BaseModel):
    ice_servers: list[dict[str, Any]]
    ring_timeout_seconds: int


class CallItem(BaseModel):
    id: int
    conversation_id: int
    caller_id: int
    callee_id: Optional[int] = None
    kind: str = "direct"
    media: str
    status: str
    started_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    created_at: Optional[datetime] = None
    peer_id: Optional[int] = None
    peer_name: Optional[str] = None
    peer_avatar_url: Optional[str] = None
    is_caller: bool = False
    ring_timeout_seconds: int = 60
    participants: list[dict[str, Any]] = Field(default_factory=list)

    class Config:
        from_attributes = True


def _call_item(db: Session, call, viewer_id: int) -> CallItem:
    kind = getattr(call, "kind", None) or "direct"
    peer_id = None
    peer = None
    if kind != "group" and call.callee_id is not None:
        peer_id = call.callee_id if viewer_id == call.caller_id else call.caller_id
        peer = db.query(User).filter(User.id == peer_id).first()
    participants: list[dict[str, Any]] = []
    if kind == "group":
        try:
            participants = CallService(db).list_participants(viewer_id, call.id)
        except Exception:
            participants = []
    return CallItem(
        id=call.id,
        conversation_id=call.conversation_id,
        caller_id=call.caller_id,
        callee_id=call.callee_id,
        kind=kind,
        media=call.media,
        status=call.status,
        started_at=call.started_at,
        ended_at=call.ended_at,
        created_at=call.created_at,
        peer_id=peer_id,
        peer_name=peer.name if peer else None,
        peer_avatar_url=getattr(peer, "avatar_url", None) if peer else None,
        is_caller=viewer_id == call.caller_id,
        ring_timeout_seconds=ring_timeout_seconds(),
        participants=participants,
    )


def _after_terminal(db: Session, call) -> None:
    CallService.publish_history_events(db, call)


@router.get("/ice-servers", response_model=IceServersResponse)
async def get_ice_servers(
    current_user: User = Depends(get_current_user_required),
):
    return IceServersResponse(
        ice_servers=CallService.ice_servers(),
        ring_timeout_seconds=ring_timeout_seconds(),
    )


@router.post("", response_model=CallItem)
async def create_call(
    body: CreateCallRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = CallService(db)
    call = service.create_call(
        current_user.id,
        conversation_id=body.conversation_id,
        media=body.media,
    )
    db.commit()
    db.refresh(call)
    # Notify only after commit so callee GET /calls/{id} cannot 404.
    if getattr(call, "kind", "direct") == "group":
        service.notify_group_incoming(call)
    else:
        service.notify_incoming(call)
    return _call_item(db, call, current_user.id)


@router.get("/{call_id}", response_model=CallItem)
async def get_call(
    call_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = CallService(db)
    call = service.get_call_for_user(current_user.id, call_id)
    db.commit()
    _after_terminal(db, call)
    return _call_item(db, call, current_user.id)


@router.post("/{call_id}/answer", response_model=CallItem)
async def answer_call(
    call_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = CallService(db)
    call = service.answer_call(current_user.id, call_id)
    db.commit()
    db.refresh(call)
    _after_terminal(db, call)
    return _call_item(db, call, current_user.id)


@router.post("/{call_id}/reject", response_model=CallItem)
async def reject_call(
    call_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = CallService(db)
    call = service.reject_call(current_user.id, call_id)
    db.commit()
    db.refresh(call)
    _after_terminal(db, call)
    return _call_item(db, call, current_user.id)


@router.post("/{call_id}/cancel", response_model=CallItem)
async def cancel_call(
    call_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = CallService(db)
    call = service.cancel_call(current_user.id, call_id)
    db.commit()
    db.refresh(call)
    _after_terminal(db, call)
    return _call_item(db, call, current_user.id)


@router.post("/{call_id}/end", response_model=CallItem)
async def end_call(
    call_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = CallService(db)
    call = service.end_call(current_user.id, call_id)
    db.commit()
    db.refresh(call)
    _after_terminal(db, call)
    return _call_item(db, call, current_user.id)


@router.post("/{call_id}/signal", response_model=CallItem)
async def signal_call(
    call_id: int,
    body: CallSignalRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = CallService(db)
    call = service.relay_signal(
        current_user.id,
        call_id,
        kind=body.kind,
        payload=body.payload,
        to_user_id=body.to_user_id,
    )
    db.commit()
    db.refresh(call)
    return _call_item(db, call, current_user.id)


@router.get("/{call_id}/participants")
async def list_call_participants(
    call_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = CallService(db)
    return {"participants": service.list_participants(current_user.id, call_id)}


@router.post("/{call_id}/invite", response_model=CallItem)
async def invite_to_call(
    call_id: int,
    body: InviteCallRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = CallService(db)
    call = service.invite_to_group_call(current_user.id, call_id, body.user_id)
    db.commit()
    db.refresh(call)
    # Push/SSE after commit so GET /calls/{id} cannot 404 for the invitee.
    service.notify_group_incoming(call)
    return _call_item(db, call, current_user.id)
