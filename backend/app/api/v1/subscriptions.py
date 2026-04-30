"""
API endpoints для подписок H.A.N. Plus
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
from datetime import datetime
from app.core.database import get_db
from app.api.dependencies import get_current_user_required
from app.models.user import User
from app.models.subscription import Subscription
from app.services.subscription_service import SubscriptionService

router = APIRouter()


class CreateSubscriptionRequest(BaseModel):
    plan: str  # monthly | yearly
    payment_provider: str  # stripe | paypal | apple | google
    payment_provider_subscription_id: str
    amount: float
    currency: str = "USD"


class SubscriptionResponse(BaseModel):
    id: int
    plan: str
    status: str
    payment_provider: Optional[str] = None
    amount: float
    currency: str
    started_at: datetime
    expires_at: Optional[datetime] = None
    auto_renew: bool
    
    class Config:
        from_attributes = True


@router.get("/status")
async def get_subscription_status(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Получить статус подписки текущего пользователя"""
    subscription_service = SubscriptionService(db)
    subscription = subscription_service.get_user_subscription(current_user.id)
    is_plus = subscription_service.is_user_plus(current_user.id)
    
    if not subscription:
        return {
            "is_plus": False,
            "subscription": None,
            "subscription_type": current_user.subscription_type or "free",
        }
    
    return {
        "is_plus": is_plus,
        "subscription": SubscriptionResponse.model_validate(subscription),
        "subscription_type": current_user.subscription_type or "free",
        "expires_at": subscription.expires_at.isoformat() if subscription.expires_at else None,
    }


@router.post("/create")
async def create_subscription(
    request: CreateSubscriptionRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Создать подписку (после успешной оплаты)"""
    # В реальности здесь должна быть проверка платежа через webhook от платежной системы
    # Пока это заглушка для тестирования
    
    subscription_service = SubscriptionService(db)
    
    try:
        subscription = subscription_service.create_subscription(
            user_id=current_user.id,
            plan=request.plan,
            payment_provider=request.payment_provider,
            payment_provider_subscription_id=request.payment_provider_subscription_id,
            amount=request.amount,
            currency=request.currency
        )
        
        return {
            "success": True,
            "subscription": SubscriptionResponse.model_validate(subscription),
            "message": "Subscription created successfully"
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Failed to create subscription: {str(e)}"
        )


@router.post("/cancel")
async def cancel_subscription(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Запросить отмену подписки через поддержку"""
    # Проверяем наличие активной подписки
    subscription_service = SubscriptionService(db)
    subscription = subscription_service.get_user_subscription(current_user.id)
    
    if not subscription:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active subscription found"
        )
    
    # Проверяем, нет ли уже открытого обращения на отмену
    from app.models.support_ticket import SupportTicket
    existing_ticket = db.query(SupportTicket).filter(
        SupportTicket.user_id == current_user.id,
        SupportTicket.type == "cancel_subscription",
        SupportTicket.status.in_(["open", "in_progress"])
    ).first()
    
    if existing_ticket:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You already have an open request to cancel subscription. Please wait for processing."
        )
    
    # Создаем обращение в поддержку
    ticket = SupportTicket(
        user_id=current_user.id,
        type="cancel_subscription",
        subject="Request to cancel H.A.N. Plus subscription",
        message="I would like to cancel my H.A.N. Plus subscription.",
        status="open",
        related_entity_type="subscription",
        related_entity_id=subscription.id
    )
    
    db.add(ticket)
    db.commit()
    db.refresh(ticket)
    
    return {
        "success": True,
        "ticket_id": ticket.id,
        "message": "Your request to cancel subscription has been submitted to support. We will process it soon.",
        "note": "Your subscription will remain active until the expiration date after processing"
    }


@router.get("/history")
async def get_subscription_history(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Получить историю подписок пользователя"""
    subscriptions = db.query(Subscription).filter(
        Subscription.user_id == current_user.id
    ).order_by(Subscription.created_at.desc()).limit(10).all()
    
    return {
        "subscriptions": [
            SubscriptionResponse.model_validate(sub) for sub in subscriptions
        ]
    }

