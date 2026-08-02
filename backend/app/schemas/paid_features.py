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


class ChannelSubscriptionInfo(BaseModel):
    channel_id: int
    status: str
    amount_stars: int = 0
    expires_at: Optional[datetime] = None
    auto_renew: bool = False
    is_active: bool = False
    monthly_price_stars: int = 0


class UpdateChannelSubscriptionRequest(BaseModel):
    auto_renew: bool


class PaidMessageExceptionItem(BaseModel):
    id: int
    name: Optional[str] = None
    username: Optional[str] = None
    avatar_url: Optional[str] = None

    class Config:
        from_attributes = True


class AddPaidMessageExceptionRequest(BaseModel):
    user_id: int = Field(gt=0)


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
    is_limited: bool = False
    total_supply: Optional[int] = None
    sold_count: int = 0
    upgrade_stars: int = 0
    transfer_stars: int = 0
    remaining: Optional[int] = None

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
    user_gift_id: Optional[int] = None


class UserStarGiftItem(BaseModel):
    id: int
    owner_id: int
    sender_id: Optional[int] = None
    gift_id: Optional[int] = None
    message_id: Optional[int] = None
    stars: int
    slug: str
    title: str
    emoji: str
    note: Optional[str] = None
    status: str
    is_displayed: bool = True
    is_collectible: bool = False
    serial: Optional[int] = None
    transferred_from_user_id: Optional[int] = None
    converted_at: Optional[datetime] = None
    created_at: datetime
    upgrade_stars: int = 0
    transfer_stars: int = 0
    total_supply: Optional[int] = None

    class Config:
        from_attributes = True


class UserStarGiftsResponse(BaseModel):
    gifts: List[UserStarGiftItem]


class SetUserStarGiftDisplayRequest(BaseModel):
    displayed: bool


class TransferUserStarGiftRequest(BaseModel):
    to_user_id: int = Field(gt=0)


class ConvertUserStarGiftResponse(BaseModel):
    gift: UserStarGiftItem
    balance: int


class CreateStarGiveawayRequest(BaseModel):
    prize_stars: int = Field(ge=1, le=100000)
    winners_count: int = Field(default=1, ge=1, le=100)
    duration_hours: int = Field(default=24, ge=1, le=24 * 30)
    title: Optional[str] = Field(default=None, max_length=160)


class StarGiveawayItem(BaseModel):
    id: int
    channel_id: int
    creator_user_id: int
    prize_stars: int
    winners_count: int
    total_escrow_stars: int
    status: str
    ends_at: datetime
    require_membership: bool = True
    participants_count: int = 0
    title: Optional[str] = None
    completed_at: Optional[datetime] = None
    created_at: datetime
    joined_by_me: bool = False
    is_winner: bool = False

    class Config:
        from_attributes = True


class StarGiveawaysResponse(BaseModel):
    giveaways: List[StarGiveawayItem]


class CreateStarInvoiceRequest(BaseModel):
    title: str = Field(min_length=1, max_length=160)
    amount_stars: int = Field(ge=1, le=100000)
    description: Optional[str] = Field(default=None, max_length=512)
    payload: Optional[str] = Field(default=None, max_length=256)
    expires_in_hours: int = Field(default=24, ge=1, le=24 * 30)


class StarInvoiceItem(BaseModel):
    id: int
    bot_id: int
    creator_user_id: int
    payer_user_id: Optional[int] = None
    title: str
    description: Optional[str] = None
    amount_stars: int
    payload: Optional[str] = None
    status: str
    expires_at: Optional[datetime] = None
    paid_at: Optional[datetime] = None
    created_at: datetime
    bot_username: Optional[str] = None
    bot_name: Optional[str] = None

    class Config:
        from_attributes = True


class PayStarInvoiceResponse(BaseModel):
    invoice: StarInvoiceItem
    balance: int

