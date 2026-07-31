"""Telegram-like paid features API."""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user_required
from app.core.database import get_db
from app.models.paid_features import StarTransaction
from app.models.user import User
from app.schemas.paid_features import (
    BoostPostRequest,
    BoostPostResponse,
    DonateStarsRequest,
    DonateStarsResponse,
    CreatorPayoutRequestCreate,
    CreatorPayoutResponse,
    CreatorPayoutReviewRequest,
    PurchaseMessageRequest,
    PurchaseMessageResponse,
    PurchasePostRequest,
    PurchasePostResponse,
    SendStarGiftRequest,
    SendStarGiftResponse,
    StarGiftItem,
    StarGiftsResponse,
    StarPackage,
    StarPackagesResponse,
    StarTransactionResponse,
    StarsBalanceResponse,
    SubscribeChannelRequest,
    SubscribeChannelResponse,
)
from app.services.paid_features_service import PaidFeaturesService

router = APIRouter()

STAR_PACKAGES = [
    StarPackage(id="stars_100", stars=100, price_rub=99, title="100 звёзд"),
    StarPackage(id="stars_500", stars=500, price_rub=449, title="500 звёзд"),
    StarPackage(id="stars_1200", stars=1200, price_rub=990, title="1200 звёзд"),
]


@router.get("/stars/packages", response_model=StarPackagesResponse)
async def list_star_packages(_: User = Depends(get_current_user_required)):
    return StarPackagesResponse(packages=STAR_PACKAGES)


@router.get("/stars/balance", response_model=StarsBalanceResponse)
async def get_stars_balance(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = PaidFeaturesService(db)
    creator = service.creator_balance(current_user.id)
    return StarsBalanceResponse(
        balance=service.star_balance(current_user.id),
        creator_available_stars=creator.available_stars or 0,
        creator_pending_stars=creator.pending_stars or 0,
    )


@router.get("/stars/transactions", response_model=list[StarTransactionResponse])
async def list_star_transactions(
    limit: int = 30,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    limit = max(1, min(limit, 100))
    return (
        db.query(StarTransaction)
        .filter(StarTransaction.user_id == current_user.id)
        .order_by(StarTransaction.created_at.desc(), StarTransaction.id.desc())
        .limit(limit)
        .all()
    )


@router.post("/content/{post_id}/purchase", response_model=PurchasePostResponse)
async def purchase_paid_content(
    post_id: int,
    request: PurchasePostRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = PaidFeaturesService(db)
    purchase = service.purchase_post(
        current_user.id,
        post_id,
        idempotency_key=request.idempotency_key,
    )
    db.commit()
    return PurchasePostResponse(
        post_id=post_id,
        purchased=True,
        amount_stars=purchase.amount_stars,
        balance=service.star_balance(current_user.id),
    )


@router.post("/stars/donate", response_model=DonateStarsResponse)
async def donate_stars(
    request: DonateStarsRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    if request.recipient_id == current_user.id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot donate to yourself")
    service = PaidFeaturesService(db)
    tx = service.donate(
        current_user.id,
        request.recipient_id,
        request.amount_stars,
        message=request.message,
    )
    db.commit()
    return DonateStarsResponse(transaction_id=tx.id, balance=service.star_balance(current_user.id))


@router.post("/channels/{channel_id}/subscribe", response_model=SubscribeChannelResponse)
async def subscribe_paid_channel(
    channel_id: int,
    request: SubscribeChannelRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = PaidFeaturesService(db)
    subscription = service.subscribe_channel(
        current_user.id,
        channel_id,
        months=request.months,
        auto_renew=request.auto_renew,
    )
    db.commit()
    return SubscribeChannelResponse(
        channel_id=channel_id,
        expires_at=subscription.expires_at,
        amount_stars=subscription.amount_stars,
        auto_renew=subscription.auto_renew,
        balance=service.star_balance(current_user.id),
    )


@router.post("/posts/{post_id}/boost", response_model=BoostPostResponse)
async def boost_post(
    post_id: int,
    request: BoostPostRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = PaidFeaturesService(db)
    boost = service.boost_post(
        current_user.id,
        post_id,
        request.amount_stars,
        duration_days=request.duration_days,
    )
    db.commit()
    return BoostPostResponse(
        boost_id=boost.id,
        post_id=post_id,
        expires_at=boost.expires_at,
        balance=service.star_balance(current_user.id),
    )


@router.post("/payouts/request", response_model=CreatorPayoutResponse)
async def request_creator_payout(
    request: CreatorPayoutRequestCreate,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = PaidFeaturesService(db)
    payout = service.request_creator_payout(
        current_user.id,
        request.amount_stars,
        note=request.note,
    )
    db.commit()
    db.refresh(payout)
    return payout


@router.get("/payouts/me", response_model=list[CreatorPayoutResponse])
async def list_my_payouts(
    limit: int = 30,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = PaidFeaturesService(db)
    return service.list_creator_payouts(current_user.id, limit=limit)


@router.post("/payouts/{payout_id}/review", response_model=CreatorPayoutResponse)
async def review_payout(
    payout_id: int,
    request: CreatorPayoutReviewRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    if not current_user.is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required")
    service = PaidFeaturesService(db)
    payout = service.review_payout(
        payout_id,
        reviewer_user_id=current_user.id,
        approve=request.approve,
        note=request.note,
    )
    db.commit()
    db.refresh(payout)
    return payout


@router.post("/messages/{message_id}/purchase", response_model=PurchaseMessageResponse)
async def purchase_paid_message(
    message_id: int,
    request: PurchaseMessageRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = PaidFeaturesService(db)
    unlock = service.purchase_message(
        current_user.id,
        message_id,
        idempotency_key=request.idempotency_key,
    )
    db.commit()
    return PurchaseMessageResponse(
        message_id=message_id,
        purchased=True,
        amount_stars=unlock.amount_stars,
        balance=service.star_balance(current_user.id),
    )


@router.get("/gifts", response_model=StarGiftsResponse)
async def list_star_gifts(
    _: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = PaidFeaturesService(db)
    gifts = service.list_star_gifts()
    return StarGiftsResponse(gifts=[StarGiftItem.model_validate(g) for g in gifts])


@router.post("/gifts/{gift_id}/send", response_model=SendStarGiftResponse)
async def send_star_gift(
    gift_id: int,
    request: SendStarGiftRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    import json

    from app.models.conversation import ConversationMember
    from app.services.chat_event_bus import publish as publish_chat_event
    from app.services.user_event_bus import publish_user_event

    service = PaidFeaturesService(db)
    gift = next((g for g in service.list_star_gifts() if g.id == gift_id), None)
    if gift is None:
        # Still allow send_star_gift to raise 404 with its own lookup
        pass
    msg = service.send_star_gift(
        current_user.id,
        gift_id=gift_id,
        conversation_id=request.conversation_id,
        message=request.message,
    )
    stars = int(gift.stars) if gift else 0
    if not stars:
        try:
            stars = int(json.loads(msg.content or "{}").get("stars") or 0)
        except Exception:
            stars = 0
    db.commit()
    db.refresh(msg)
    payload = {
        "id": msg.id,
        "conversation_id": msg.conversation_id,
        "sender_id": msg.sender_id,
        "type": msg.type,
        "content": msg.content,
        "media_url": msg.media_url,
        "reply_to_message_id": msg.reply_to_message_id,
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
        request.conversation_id,
        {"type": "message.new", "message": payload},
    )
    member_ids = (
        db.query(ConversationMember.user_id)
        .filter(ConversationMember.conversation_id == request.conversation_id)
        .all()
    )
    for (user_id,) in member_ids:
        if user_id == current_user.id:
            continue
        publish_user_event(
            user_id,
            {"event": "chat.inbox", "conversation_id": request.conversation_id},
        )
    return SendStarGiftResponse(
        message_id=msg.id,
        conversation_id=request.conversation_id,
        gift_id=gift_id,
        stars=stars,
        balance=service.star_balance(current_user.id),
    )

