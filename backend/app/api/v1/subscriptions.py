"""
API endpoints для подписок (тарифы free | ai | creator | pro).
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
from datetime import datetime
import logging

from app.core.database import get_db
from app.core.config import settings
from app.api.dependencies import get_current_user_required
from app.models.user import User
from app.models.subscription import Subscription
from app.models.support_ticket import SupportTicket
from app.services.subscription_service import SubscriptionService

router = APIRouter()
_log = logging.getLogger(__name__)


class CreateSubscriptionRequest(BaseModel):
    plan: str
    product: str = "pro"
    payment_provider: str
    payment_provider_subscription_id: str
    amount: float
    currency: str = "RUB"


class SubscriptionResponse(BaseModel):
    id: int
    plan: str
    product: str = "pro"
    status: str
    payment_provider: Optional[str] = None
    amount: float
    currency: str
    started_at: datetime
    expires_at: Optional[datetime] = None
    auto_renew: bool

    class Config:
        from_attributes = True


class StartTrialRequest(BaseModel):
    product: str = "ai"  # ai | pro


class CancelSubscriptionRequest(BaseModel):
    cancellation_reason: str
    improvement_feedback: Optional[str] = None


@router.post("/trial")
async def start_subscription_trial(
    request: StartTrialRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Бесплатный пробный период (без ЮKassa), только ai/pro."""
    product = (request.product or "ai").strip().lower()
    if product not in ("ai", "pro"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Trial is only available for 'ai' or 'pro'",
        )
    svc = SubscriptionService(db)
    if not svc.trial_eligible(current_user.id, product):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Trial is not available for this account",
        )
    try:
        sub = svc.start_trial(current_user.id, product)
        from app.services.analytics_service import AnalyticsService

        AnalyticsService(db).log_event(
            event_type="subscription_trial_started",
            entity_type="user",
            entity_id=current_user.id,
            user_id=current_user.id,
            metadata={"product": product},
        )
        db.commit()
        try:
            from app.core.redis_client import get_redis
            from app.services.feed_service import FeedService

            FeedService(db, get_redis()).invalidate_feed_cache(current_user.id)
        except Exception as e:
            _log.warning("Feed cache invalidate after trial: %s", e)
        return {
            "success": True,
            "subscription": SubscriptionResponse.model_validate(sub),
            "message": f"Пробный период H.A.N. {product.upper()} активирован",
        }
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.get("/status")
async def get_subscription_status(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Статус подписки в формате ТЗ."""
    return SubscriptionService(db).get_status_dict(current_user.id)


@router.post("/create")
async def create_subscription(
    request: CreateSubscriptionRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    if settings.APP_ENV == "production" and not settings.ALLOW_DIRECT_SUBSCRIPTION_CREATE:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "Direct subscription creation is disabled in production. "
                "Use the payment provider flow (webhooks provision the subscription)."
            ),
        )

    subscription_service = SubscriptionService(db)
    try:
        subscription = subscription_service.create_subscription(
            user_id=current_user.id,
            plan=request.plan,
            product=request.product,
            payment_provider=request.payment_provider,
            payment_provider_subscription_id=request.payment_provider_subscription_id,
            amount=request.amount,
            currency=request.currency,
        )
        return {
            "success": True,
            "subscription": SubscriptionResponse.model_validate(subscription),
            "message": "Subscription created successfully",
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Failed to create subscription: {str(e)}",
        )


@router.post("/cancel")
async def cancel_subscription(
    request: CancelSubscriptionRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    subscription_service = SubscriptionService(db)
    subscription = subscription_service.get_user_subscription(current_user.id)

    if not subscription:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active subscription found",
        )

    existing_ticket = (
        db.query(SupportTicket)
        .filter(
            SupportTicket.user_id == current_user.id,
            SupportTicket.type == "cancel_subscription",
            SupportTicket.status.in_(["open", "in_progress"]),
        )
        .first()
    )

    if existing_ticket:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You already have an open request to cancel subscription.",
        )

    message_lines = [
        "Запрос на отмену подписки.",
        f"Причина: {request.cancellation_reason.strip()}",
    ]
    feedback = (request.improvement_feedback or "").strip()
    if feedback:
        message_lines.append(f"Что доработать: {feedback}")

    ticket = SupportTicket(
        user_id=current_user.id,
        type="cancel_subscription",
        subject="Запрос на отмену подписки",
        message="\n".join(message_lines),
        status="open",
        related_entity_type="subscription",
        related_entity_id=subscription.id,
    )

    db.add(ticket)
    db.commit()
    db.refresh(ticket)

    return {
        "success": True,
        "ticket_id": ticket.id,
        "message": "Your cancellation request has been submitted.",
        "note": "Subscription remains active until expiration after processing.",
    }


@router.get("/history")
async def get_subscription_history(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    subscriptions = (
        db.query(Subscription)
        .filter(Subscription.user_id == current_user.id)
        .order_by(Subscription.created_at.desc())
        .limit(10)
        .all()
    )

    return {
        "subscriptions": [
            SubscriptionResponse.model_validate(sub) for sub in subscriptions
        ]
    }
