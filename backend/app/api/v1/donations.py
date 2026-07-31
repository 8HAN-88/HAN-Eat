"""
API для донатов (поддержка авторов)
"""
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.api.dependencies import get_current_user_required as get_current_user
from app.models.user import User
from app.models.donation import Donation
from app.models.community import Channel
from app.models.post import Post

router = APIRouter(prefix="/donations", tags=["Donations"])


# === Schemas ===

class DonationCreateRequest(BaseModel):
    recipient_id: int
    channel_id: Optional[int] = None
    post_id: Optional[int] = None
    amount_stars: int = Field(..., ge=1, le=100000)
    message: Optional[str] = Field(None, max_length=500)


class DonationResponse(BaseModel):
    id: int
    sender_id: Optional[int]
    recipient_id: int
    channel_id: Optional[int]
    post_id: Optional[int]
    amount_stars: int
    message: Optional[str]
    status: str
    created_at: str

    class Config:
        from_attributes = True


# === Endpoints ===

@router.post("", response_model=DonationResponse, status_code=status.HTTP_201_CREATED)
async def create_donation(
    payload: DonationCreateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Отправить донат автору / каналу / посту.
    В MVP используем Stars (внутренняя валюта).
    """
    # Проверка получателя
    recipient = db.query(User).filter(User.id == payload.recipient_id).first()
    if not recipient:
        raise HTTPException(status_code=404, detail="Recipient not found")

    if recipient.id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot donate to yourself")

    # Проверка канала (если указан)
    if payload.channel_id:
        channel = db.query(Channel).filter(Channel.id == payload.channel_id).first()
        if not channel or int(channel.admin_user_id) != int(payload.recipient_id):
            raise HTTPException(status_code=400, detail="Invalid channel")

    # Проверка поста (если указан)
    if payload.post_id:
        post = db.query(Post).filter(Post.id == payload.post_id).first()
        if not post or post.user_id != payload.recipient_id:
            raise HTTPException(status_code=400, detail="Invalid post")

    from app.services.paid_features_service import PaidFeaturesService

    service = PaidFeaturesService(db)
    # Списываем ★ и зачисляем автору (как /paid/stars/donate).
    service.donate(
        current_user.id,
        payload.recipient_id,
        payload.amount_stars,
        message=payload.message,
    )

    donation = Donation(
        sender_id=current_user.id,
        recipient_id=payload.recipient_id,
        channel_id=payload.channel_id,
        post_id=payload.post_id,
        amount_stars=payload.amount_stars,
        message=payload.message,
        status="completed",
    )
    db.add(donation)
    db.commit()
    db.refresh(donation)

    return DonationResponse(
        id=donation.id,
        sender_id=donation.sender_id,
        recipient_id=donation.recipient_id,
        channel_id=donation.channel_id,
        post_id=donation.post_id,
        amount_stars=donation.amount_stars,
        message=donation.message,
        status=donation.status,
        created_at=donation.created_at.isoformat(),
    )


@router.get("/received", response_model=List[DonationResponse])
async def list_received_donations(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    limit: int = 50,
    offset: int = 0,
):
    """История полученных донатов"""
    donations = (
        db.query(Donation)
        .filter(Donation.recipient_id == current_user.id)
        .order_by(Donation.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )

    return [
        DonationResponse(
            id=d.id,
            sender_id=d.sender_id,
            recipient_id=d.recipient_id,
            channel_id=d.channel_id,
            post_id=d.post_id,
            amount_stars=d.amount_stars,
            message=d.message,
            status=d.status,
            created_at=d.created_at.isoformat(),
        )
        for d in donations
    ]


@router.get("/sent", response_model=List[DonationResponse])
async def list_sent_donations(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    limit: int = 50,
    offset: int = 0,
):
    """История отправленных донатов"""
    donations = (
        db.query(Donation)
        .filter(Donation.sender_id == current_user.id)
        .order_by(Donation.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )

    return [
        DonationResponse(
            id=d.id,
            sender_id=d.sender_id,
            recipient_id=d.recipient_id,
            channel_id=d.channel_id,
            post_id=d.post_id,
            amount_stars=d.amount_stars,
            message=d.message,
            status=d.status,
            created_at=d.created_at.isoformat(),
        )
        for d in donations
    ]
