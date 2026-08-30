"""Ассистент чата: переписать / ответить / сжать."""
from typing import Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user_required
from app.core.database import get_db
from app.models.user import User
from app.services.ai_assist_service import assist_text
from app.services.subscription_service import SubscriptionService

router = APIRouter()


class AssistRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=4000)
    mode: Optional[Literal["rewrite", "reply", "summarize"]] = "rewrite"


@router.post("/assist")
async def chat_assist(
    body: AssistRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    text = (body.text or "").strip()
    if not text:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="empty_text")
    svc = SubscriptionService(db)
    if not svc.has_ai_access(current_user.id):
        from app.core.entitlements import HAN_AI_REQUIRED_CODE

        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail={
                "code": HAN_AI_REQUIRED_CODE,
                "message": "Ассистент доступен с AI-функциями подписки",
            },
        )
    priority = svc.has_entitlement(current_user.id, "ai_priority_speed")
    return assist_text(text, body.mode or "rewrite", priority=priority)
