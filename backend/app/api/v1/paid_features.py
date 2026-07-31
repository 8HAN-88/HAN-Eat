"""Telegram-like paid features API."""
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user_required
from app.core.database import get_db
from app.models.paid_features import StarTransaction
from app.models.user import User
from app.schemas.paid_features import (
    AddPaidMessageExceptionRequest,
    BoostPostRequest,
    BoostPostResponse,
    ChannelSubscriptionInfo,
    DonateStarsRequest,
    DonateStarsResponse,
    CreatorPayoutRequestCreate,
    CreatorPayoutResponse,
    CreatorPayoutReviewRequest,
    PaidMessageExceptionItem,
    PurchaseMessageRequest,
    PurchaseMessageResponse,
    PurchasePostRequest,
    PurchasePostResponse,
    ConvertUserStarGiftResponse,
    SendStarGiftRequest,
    SendStarGiftResponse,
    SetUserStarGiftDisplayRequest,
    StarGiftItem,
    StarGiftsResponse,
    StarPackage,
    StarPackagesResponse,
    StarTransactionResponse,
    StarsBalanceResponse,
    SubscribeChannelRequest,
    SubscribeChannelResponse,
    UpdateChannelSubscriptionRequest,
    UserStarGiftItem,
    UserStarGiftsResponse,
)
from app.models.community import Channel
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
    # Keep /donations history in sync with Stars tip path.
    from app.models.donation import Donation

    db.add(
        Donation(
            sender_id=current_user.id,
            recipient_id=request.recipient_id,
            amount_stars=request.amount_stars,
            message=request.message,
            status="completed",
        )
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


def _channel_subscription_info(
    service: PaidFeaturesService, user_id: int, channel_id: int
) -> ChannelSubscriptionInfo:
    channel = (
        service.db.query(Channel).filter(Channel.id == channel_id).first()
    )
    if not channel:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Channel not found")
    monthly = int(getattr(channel, "monthly_price_stars", 0) or 0)
    sub = service.get_channel_subscription(user_id, channel_id)
    now = datetime.utcnow()
    if sub is None:
        return ChannelSubscriptionInfo(
            channel_id=channel_id,
            status="none",
            monthly_price_stars=monthly,
        )
    is_active = (
        sub.status == "active"
        and sub.expires_at is not None
        and sub.expires_at > now
    )
    status_out = (
        "active"
        if is_active
        else ("expired" if sub.status == "active" else (sub.status or "expired"))
    )
    return ChannelSubscriptionInfo(
        channel_id=channel_id,
        status=status_out,
        amount_stars=sub.amount_stars,
        expires_at=sub.expires_at,
        auto_renew=bool(sub.auto_renew) if is_active else False,
        is_active=is_active,
        monthly_price_stars=monthly,
    )


@router.get(
    "/channels/{channel_id}/subscription",
    response_model=ChannelSubscriptionInfo,
)
async def get_channel_subscription(
    channel_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = PaidFeaturesService(db)
    return _channel_subscription_info(service, current_user.id, channel_id)


@router.patch(
    "/channels/{channel_id}/subscription",
    response_model=ChannelSubscriptionInfo,
)
async def update_channel_subscription(
    channel_id: int,
    request: UpdateChannelSubscriptionRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = PaidFeaturesService(db)
    service.update_channel_subscription_auto_renew(
        current_user.id, channel_id, auto_renew=request.auto_renew
    )
    db.commit()
    return _channel_subscription_info(service, current_user.id, channel_id)


@router.post(
    "/channels/{channel_id}/subscription/cancel",
    response_model=ChannelSubscriptionInfo,
)
async def cancel_channel_subscription(
    channel_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = PaidFeaturesService(db)
    service.cancel_channel_subscription(current_user.id, channel_id)
    db.commit()
    return _channel_subscription_info(service, current_user.id, channel_id)


@router.get(
    "/message-exceptions",
    response_model=list[PaidMessageExceptionItem],
)
async def list_paid_message_exceptions(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = PaidFeaturesService(db)
    users = service.list_paid_message_exceptions(current_user.id)
    return [
        PaidMessageExceptionItem(
            id=u.id,
            name=u.name,
            username=u.username,
            avatar_url=u.avatar_url,
        )
        for u in users
    ]


@router.post(
    "/message-exceptions",
    response_model=PaidMessageExceptionItem,
    status_code=status.HTTP_201_CREATED,
)
async def add_paid_message_exception(
    request: AddPaidMessageExceptionRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = PaidFeaturesService(db)
    user = service.add_paid_message_exception(current_user.id, request.user_id)
    db.commit()
    return PaidMessageExceptionItem(
        id=user.id,
        name=user.name,
        username=user.username,
        avatar_url=user.avatar_url,
    )


@router.delete(
    "/message-exceptions/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def remove_paid_message_exception(
    user_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = PaidFeaturesService(db)
    service.remove_paid_message_exception(current_user.id, user_id)
    db.commit()


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
        idempotency_key=request.idempotency_key,
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
    user_gift_id = None
    try:
        import json as _json

        payload = _json.loads(msg.content or "{}")
        if isinstance(payload, dict):
            user_gift_id = payload.get("user_gift_id")
    except Exception:
        user_gift_id = None
    return SendStarGiftResponse(
        message_id=msg.id,
        conversation_id=request.conversation_id,
        gift_id=gift_id,
        stars=stars,
        balance=service.star_balance(current_user.id),
        user_gift_id=int(user_gift_id) if user_gift_id else None,
    )


@router.get("/gifts/inventory", response_model=UserStarGiftsResponse)
async def list_my_star_gifts(
    include_converted: bool = False,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = PaidFeaturesService(db)
    gifts = service.list_user_star_gifts(
        current_user.id, include_converted=include_converted
    )
    return UserStarGiftsResponse(
        gifts=[UserStarGiftItem.model_validate(g) for g in gifts]
    )


@router.get("/users/{user_id}/gifts", response_model=UserStarGiftsResponse)
async def list_user_displayed_gifts(
    user_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = PaidFeaturesService(db)
    gifts = service.list_user_star_gifts(user_id, displayed_only=True, limit=40)
    return UserStarGiftsResponse(
        gifts=[UserStarGiftItem.model_validate(g) for g in gifts]
    )


@router.post(
    "/gifts/inventory/{user_gift_id}/convert",
    response_model=ConvertUserStarGiftResponse,
)
async def convert_my_star_gift(
    user_gift_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = PaidFeaturesService(db)
    gift = service.convert_user_star_gift(current_user.id, user_gift_id)
    db.commit()
    db.refresh(gift)
    return ConvertUserStarGiftResponse(
        gift=UserStarGiftItem.model_validate(gift),
        balance=service.star_balance(current_user.id),
    )


@router.post(
    "/gifts/inventory/{user_gift_id}/keep",
    response_model=UserStarGiftItem,
)
async def keep_my_star_gift(
    user_gift_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = PaidFeaturesService(db)
    gift = service.keep_user_star_gift(current_user.id, user_gift_id)
    db.commit()
    db.refresh(gift)
    return UserStarGiftItem.model_validate(gift)


@router.patch(
    "/gifts/inventory/{user_gift_id}/display",
    response_model=UserStarGiftItem,
)
async def set_my_star_gift_display(
    user_gift_id: int,
    request: SetUserStarGiftDisplayRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = PaidFeaturesService(db)
    gift = service.set_user_star_gift_displayed(
        current_user.id, user_gift_id, displayed=request.displayed
    )
    db.commit()
    db.refresh(gift)
    return UserStarGiftItem.model_validate(gift)

