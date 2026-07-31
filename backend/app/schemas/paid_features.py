from datetime import datetime
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class StarsBalanceResponse(BaseModel):
    balance: int
    creator_available_stars: int = 0
    creator_pending_stars: int = 0


class StarPackage(BaseModel):
    id: str
    stars: int
    price_rub: int
    title: str


class StarPackagesResponse(BaseModel):
    packages: List[StarPackage]


class PurchasePostRequest(BaseModel):
    idempotency_key: Optional[str] = None


class PurchasePostResponse(BaseModel):
    post_id: int
    purchased: bool
    amount_stars: int
    balance: int


class DonateStarsRequest(BaseModel):
    recipient_id: int
    amount_stars: int = Field(gt=0, le=100000)
    message: Optional[str] = None


class DonateStarsResponse(BaseModel):
    transaction_id: int
    balance: int


class SubscribeChannelRequest(BaseModel):
    months: int = Field(default=1, ge=1, le=12)
    auto_renew: bool = False


class SubscribeChannelResponse(BaseModel):
    channel_id: int
    expires_at: datetime
    amount_stars: int
    auto_renew: bool = False
    balance: int


class BoostPostRequest(BaseModel):
    amount_stars: int = Field(gt=0, le=100000)
    duration_days: int = Field(default=7, ge=1, le=30)


class BoostPostResponse(BaseModel):
    boost_id: int
    post_id: int
    expires_at: Optional[datetime]
    balance: int


class StarTransactionResponse(BaseModel):
    id: int
    amount: int
    type: str
    status: str
    counterparty_user_id: Optional[int] = None
    reference_type: Optional[str] = None
    reference_id: Optional[int] = None
    meta: Optional[Dict[str, Any]] = None
    created_at: datetime

    class Config:
        from_attributes = True


class CreatorPayoutRequestCreate(BaseModel):
    amount_stars: int = Field(gt=0, le=10_000_000)
    note: Optional[str] = Field(default=None, max_length=512)


class CreatorPayoutReviewRequest(BaseModel):
    approve: bool
    note: Optional[str] = Field(default=None, max_length=512)


class CreatorPayoutResponse(BaseModel):
    id: int
    creator_user_id: int
    amount_stars: int
    amount_rub: float
    status: str
    note: Optional[str] = None
    reviewed_by_user_id: Optional[int] = None
    reviewed_at: Optional[datetime] = None
    paid_at: Optional[datetime] = None
    created_at: datetime

    class Config:
        from_attributes = True


class PurchaseMessageRequest(BaseModel):
    idempotency_key: Optional[str] = None


class PurchaseMessageResponse(BaseModel):
    message_id: int
    purchased: bool
    amount_stars: int
    balance: int


class StarGiftItem(BaseModel):
    id: int
    slug: str
    title: str
    emoji: str
    stars: int

    class Config:
        from_attributes = True


class StarGiftsResponse(BaseModel):
    gifts: List[StarGiftItem]


class SendStarGiftRequest(BaseModel):
    conversation_id: int
    message: Optional[str] = Field(default=None, max_length=500)
    idempotency_key: Optional[str] = Field(default=None, max_length=128)


class SendStarGiftResponse(BaseModel):
    message_id: int
    conversation_id: int
    gift_id: int
    stars: int
    balance: int

