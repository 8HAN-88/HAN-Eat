"""
API endpoints для поддержки
"""
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from typing import Optional, List
from pydantic import BaseModel
from datetime import datetime
from app.core.database import get_db
from app.api.dependencies import get_current_user_required, get_current_admin_required
from app.models.user import User
from app.models.support_ticket import SupportTicket
from app.models.subscription import Subscription
from app.services.subscription_service import SubscriptionService

router = APIRouter()


class CreateTicketRequest(BaseModel):
    type: str  # cancel_subscription | technical_issue | billing | other
    subject: str
    message: str


class ResolveTicketRequest(BaseModel):
    resolution_comment: Optional[str] = None
    action: Optional[str] = None  # cancel_subscription | other (для автоматических действий)


@router.post("/tickets", status_code=status.HTTP_201_CREATED)
async def create_support_ticket(
    request: CreateTicketRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Создать обращение в поддержку"""
    # Если это запрос на отмену подписки, проверяем наличие активной подписки
    related_entity_type = None
    related_entity_id = None
    
    if request.type == "cancel_subscription":
        subscription_service = SubscriptionService(db)
        subscription = subscription_service.get_user_subscription(current_user.id)
        
        if not subscription:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No active subscription to cancel"
            )
        
        related_entity_type = "subscription"
        related_entity_id = subscription.id
    
    # Создаем обращение
    ticket = SupportTicket(
        user_id=current_user.id,
        type=request.type,
        subject=request.subject,
        message=request.message,
        status="open",
        related_entity_type=related_entity_type,
        related_entity_id=related_entity_id
    )
    
    db.add(ticket)
    db.commit()
    db.refresh(ticket)
    
    return {
        "id": ticket.id,
        "type": ticket.type,
        "status": ticket.status,
        "created_at": ticket.created_at.isoformat() if ticket.created_at else None,
        "message": "Support ticket created successfully. We will process your request soon."
    }


@router.get("/tickets")
async def get_user_tickets(
    status_filter: Optional[str] = Query(None, alias="status"),  # open | in_progress | resolved | closed
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Получить список обращений пользователя"""
    query = db.query(SupportTicket).filter(
        SupportTicket.user_id == current_user.id
    )
    
    if status_filter:
        query = query.filter(SupportTicket.status == status_filter)
    
    tickets = query.order_by(SupportTicket.created_at.desc()).limit(limit).offset(offset).all()
    
    return {
        "tickets": [
            {
                "id": t.id,
                "type": t.type,
                "subject": t.subject,
                "message": t.message,
                "status": t.status,
                "resolution_comment": t.resolution_comment,
                "created_at": t.created_at.isoformat() if t.created_at else None,
                "resolved_at": t.resolved_at.isoformat() if t.resolved_at else None,
            }
            for t in tickets
        ],
        "total": db.query(SupportTicket).filter(SupportTicket.user_id == current_user.id).count()
    }


@router.get("/tickets/{ticket_id}")
async def get_ticket(
    ticket_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """Получить детали обращения"""
    ticket = db.query(SupportTicket).filter(
        SupportTicket.id == ticket_id,
        SupportTicket.user_id == current_user.id
    ).first()
    
    if not ticket:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ticket not found"
        )
    
    return {
        "id": ticket.id,
        "type": ticket.type,
        "subject": ticket.subject,
        "message": ticket.message,
        "status": ticket.status,
        "resolution_comment": ticket.resolution_comment,
        "created_at": ticket.created_at.isoformat() if ticket.created_at else None,
        "resolved_at": ticket.resolved_at.isoformat() if ticket.resolved_at else None,
    }


@router.post("/tickets/{ticket_id}/resolve")
async def resolve_ticket(
    ticket_id: int,
    request: ResolveTicketRequest,
    current_user: User = Depends(get_current_admin_required),
    db: Session = Depends(get_db)
):
    """Обработать обращение (только для админов)"""
    
    ticket = db.query(SupportTicket).filter(
        SupportTicket.id == ticket_id
    ).first()
    
    if not ticket:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ticket not found"
        )
    
    if ticket.status in ["resolved", "closed"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ticket already resolved or closed"
        )
    
    # Автоматическая обработка для cancel_subscription
    if ticket.type == "cancel_subscription" and ticket.related_entity_type == "subscription":
        subscription_service = SubscriptionService(db)
        from app.models.subscription import Subscription
        
        subscription = db.query(Subscription).filter(
            Subscription.id == ticket.related_entity_id,
            Subscription.user_id == ticket.user_id
        ).first()
        
        if subscription:
            cancelled_subscription = subscription_service.cancel_subscription(subscription.id)
            if not cancelled_subscription:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Failed to cancel subscription"
                )
        else:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Subscription not found"
            )
    
    # Обновляем статус обращения
    ticket.status = "resolved"
    ticket.resolved_by_user_id = current_user.id
    ticket.resolution_comment = request.resolution_comment or "Request processed successfully"
    ticket.resolved_at = datetime.utcnow()
    
    db.commit()
    
    return {
        "id": ticket.id,
        "status": ticket.status,
        "resolution_comment": ticket.resolution_comment,
        "resolved_at": ticket.resolved_at.isoformat() if ticket.resolved_at else None,
        "message": "Ticket resolved successfully"
    }


@router.get("/admin/tickets")
async def get_all_tickets(
    status_filter: Optional[str] = Query(None, alias="status"),
    type_filter: Optional[str] = Query(None, alias="type"),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_admin_required),
    db: Session = Depends(get_db)
):
    """Получить все обращения (только для админов)"""
    
    query = db.query(SupportTicket)
    
    if status_filter:
        query = query.filter(SupportTicket.status == status_filter)
    
    if type_filter:
        query = query.filter(SupportTicket.type == type_filter)
    
    tickets = query.order_by(SupportTicket.created_at.desc()).limit(limit).offset(offset).all()
    
    # Обогащаем данными о пользователях
    user_ids = {t.user_id for t in tickets}
    users = db.query(User).filter(User.id.in_(user_ids)).all()
    users_dict = {u.id: u for u in users}
    
    enriched_tickets = []
    for ticket in tickets:
        user = users_dict.get(ticket.user_id)
        enriched_tickets.append({
            "id": ticket.id,
            "user": {
                "id": user.id if user else None,
                "name": user.name if user else None,
                "email": user.email if user else None,
            } if user else None,
            "type": ticket.type,
            "subject": ticket.subject,
            "message": ticket.message,
            "status": ticket.status,
            "resolution_comment": ticket.resolution_comment,
            "created_at": ticket.created_at.isoformat() if ticket.created_at else None,
            "resolved_at": ticket.resolved_at.isoformat() if ticket.resolved_at else None,
        })
    
    return {
        "tickets": enriched_tickets,
        "total": query.count()
    }

