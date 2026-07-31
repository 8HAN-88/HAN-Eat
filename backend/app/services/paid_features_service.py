"""Business logic for Telegram-like paid features."""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Optional

from fastapi import HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.community import Channel
from app.models.conversation import Conversation, ConversationMember, Message
from app.models.paid_features import (
    CreatorPayoutRequest,
    CreatorBalance,
    PaidChannelSubscription,
    PaidContentPurchase,
    PaidMessageUnlock,
    PostBoost,
    StarGift,
    StarTransaction,
)
from app.models.post import Post
from app.models.user import User


def _invalidate_user_feed_cache(db: Session, user_id: int) -> None:
    try:
        from app.core.redis_client import get_redis
        from app.services.feed_service import FeedService

        FeedService(db, get_redis()).invalidate_feed_cache(user_id)
    except Exception:
        pass


def _raise_idempotency_conflict() -> None:
    raise HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail={
            "code": "IDEMPOTENCY_KEY_REUSED",
            "message": "Этот idempotency key уже использован для другой операции",
        },
    )


def _matches_transaction(
    tx: StarTransaction,
    *,
    user_id: int,
    amount: int,
    tx_type: str,
    reference_type: Optional[str] = None,
    reference_id: Optional[int] = None,
) -> bool:
    return (
        tx.user_id == user_id
        and tx.amount == amount
        and tx.type == tx_type
        and (reference_type is None or tx.reference_type == reference_type)
        and (reference_id is None or tx.reference_id == reference_id)
    )


class PaidFeaturesService:
    def __init__(self, db: Session):
        self.db = db

    def _lock_user_wallet(self, user_id: int) -> None:
        user = (
            self.db.query(User.id)
            .filter(User.id == user_id, User.deleted_at.is_(None))
            .with_for_update()
            .first()
        )
        if not user:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    def star_balance(self, user_id: int) -> int:
        total = (
            self.db.query(func.coalesce(func.sum(StarTransaction.amount), 0))
            .filter(
                StarTransaction.user_id == user_id,
                StarTransaction.status == "completed",
            )
            .scalar()
        )
        return int(total or 0)

    def creator_balance(self, user_id: int) -> CreatorBalance:
        balance = self.db.query(CreatorBalance).filter(CreatorBalance.user_id == user_id).first()
        if balance is None:
            balance = CreatorBalance(user_id=user_id, available_stars=0, pending_stars=0, paid_out_stars=0)
            self.db.add(balance)
            self.db.flush()
        return balance

    def add_stars(
        self,
        user_id: int,
        amount: int,
        *,
        tx_type: str = "admin_adjust",
        provider: Optional[str] = None,
        provider_payment_id: Optional[str] = None,
        idempotency_key: Optional[str] = None,
        meta: Optional[dict] = None,
    ) -> StarTransaction:
        if amount <= 0:
            raise ValueError("amount must be positive")
        if idempotency_key:
            existing = (
                self.db.query(StarTransaction)
                .filter(StarTransaction.idempotency_key == idempotency_key)
                .first()
            )
            if existing:
                if not _matches_transaction(existing, user_id=user_id, amount=amount, tx_type=tx_type):
                    _raise_idempotency_conflict()
                return existing
        tx = StarTransaction(
            user_id=user_id,
            amount=amount,
            type=tx_type,
            provider=provider,
            provider_payment_id=provider_payment_id,
            idempotency_key=idempotency_key,
            meta=meta,
        )
        self.db.add(tx)
        self.db.flush()
        return tx

    def _spend_stars(
        self,
        user_id: int,
        amount: int,
        *,
        tx_type: str,
        reference_type: str,
        reference_id: int,
        counterparty_user_id: Optional[int] = None,
        idempotency_key: Optional[str] = None,
        meta: Optional[dict] = None,
    ) -> StarTransaction:
        if amount <= 0:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Amount must be positive")
        if idempotency_key:
            existing = (
                self.db.query(StarTransaction)
                .filter(StarTransaction.idempotency_key == idempotency_key)
                .first()
            )
            if existing:
                if not _matches_transaction(
                    existing,
                    user_id=user_id,
                    amount=-amount,
                    tx_type=tx_type,
                    reference_type=reference_type,
                    reference_id=reference_id,
                ):
                    _raise_idempotency_conflict()
                return existing
        self._lock_user_wallet(user_id)
        if self.star_balance(user_id) < amount:
            raise HTTPException(
                status_code=status.HTTP_402_PAYMENT_REQUIRED,
                detail={"code": "STARS_REQUIRED", "message": "Недостаточно звёзд"},
            )
        tx = StarTransaction(
            user_id=user_id,
            counterparty_user_id=counterparty_user_id,
            amount=-amount,
            type=tx_type,
            reference_type=reference_type,
            reference_id=reference_id,
            idempotency_key=idempotency_key,
            meta=meta,
        )
        self.db.add(tx)
        self.db.flush()
        return tx

    def _credit_creator(
        self,
        creator_id: int,
        amount: int,
        *,
        tx_type: str,
        reference_type: str,
        reference_id: int,
        counterparty_user_id: Optional[int],
        meta: Optional[dict] = None,
    ) -> None:
        tx = StarTransaction(
            user_id=creator_id,
            counterparty_user_id=counterparty_user_id,
            amount=amount,
            type=tx_type,
            reference_type=reference_type,
            reference_id=reference_id,
            meta=meta,
        )
        self.db.add(tx)
        balance = self.creator_balance(creator_id)
        balance.available_stars = int(balance.available_stars or 0) + amount

    def has_purchased_post(self, user_id: Optional[int], post: Post) -> bool:
        if not getattr(post, "is_paid", False):
            return True
        if user_id is None:
            return False
        if post.user_id == user_id:
            return True
        return (
            self.db.query(PaidContentPurchase.id)
            .filter(
                PaidContentPurchase.user_id == user_id,
                PaidContentPurchase.post_id == post.id,
                PaidContentPurchase.status == "completed",
            )
            .first()
            is not None
        )

    def purchase_post(self, user_id: int, post_id: int, *, idempotency_key: Optional[str] = None) -> PaidContentPurchase:
        post = self.db.query(Post).filter(Post.id == post_id, Post.deleted_at.is_(None)).first()
        if not post:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Post not found")
        if not getattr(post, "is_paid", False):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Post is not paid")
        if post.user_id == user_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Authors already own their content")
        existing = (
            self.db.query(PaidContentPurchase)
            .filter(PaidContentPurchase.user_id == user_id, PaidContentPurchase.post_id == post_id)
            .first()
        )
        if existing:
            return existing
        amount = int(getattr(post, "price_stars", 0) or 0)
        if amount <= 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Paid content price must be greater than 0 stars",
            )
        self._spend_stars(
            user_id,
            amount,
            tx_type="content_purchase",
            reference_type="post",
            reference_id=post_id,
            counterparty_user_id=post.user_id,
            idempotency_key=idempotency_key,
        )
        purchase = PaidContentPurchase(
            user_id=user_id,
            post_id=post_id,
            author_id=post.user_id,
            amount_stars=amount,
        )
        self.db.add(purchase)
        self._credit_creator(
            post.user_id,
            amount,
            tx_type="content_sale",
            reference_type="post",
            reference_id=post_id,
            counterparty_user_id=user_id,
        )
        _invalidate_user_feed_cache(self.db, user_id)
        self.db.flush()
        return purchase

    def donate(self, sender_id: int, recipient_id: int, amount: int, *, message: Optional[str] = None) -> StarTransaction:
        if sender_id == recipient_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot donate to yourself")
        recipient_exists = self.db.query(User.id).filter(User.id == recipient_id, User.deleted_at.is_(None)).first()
        if not recipient_exists:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recipient not found")
        tx = self._spend_stars(
            sender_id,
            amount,
            tx_type="donation",
            reference_type="user",
            reference_id=recipient_id,
            counterparty_user_id=recipient_id,
            meta={"message": message} if message else None,
        )
        self._credit_creator(
            recipient_id,
            amount,
            tx_type="donation_received",
            reference_type="user",
            reference_id=sender_id,
            counterparty_user_id=sender_id,
            meta={"message": message} if message else None,
        )
        return tx

    def subscribe_channel(
        self,
        user_id: int,
        channel_id: int,
        *,
        months: int = 1,
        auto_renew: bool = False,
    ) -> PaidChannelSubscription:
        if months < 1 or months > 12:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Months must be between 1 and 12")
        channel = self.db.query(Channel).filter(Channel.id == channel_id).first()
        if not channel:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Channel not found")
        if channel.admin_user_id == user_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Owner already has access")
        price = int(getattr(channel, "monthly_price_stars", 0) or 0) * months
        if not getattr(channel, "is_paid", False) or price <= 0:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Channel is not paid")
        now = datetime.utcnow()
        existing = (
            self.db.query(PaidChannelSubscription)
            .filter(PaidChannelSubscription.user_id == user_id, PaidChannelSubscription.channel_id == channel_id)
            .first()
        )
        self._spend_stars(
            user_id,
            price,
            tx_type="channel_subscription",
            reference_type="channel",
            reference_id=channel_id,
            counterparty_user_id=channel.admin_user_id,
        )
        expires_base = existing.expires_at if existing and existing.expires_at and existing.expires_at > now else now
        expires_at = expires_base + timedelta(days=30 * months)
        if existing:
            existing.amount_stars = price
            existing.status = "active"
            existing.expires_at = expires_at
            existing.auto_renew = auto_renew
            sub = existing
        else:
            sub = PaidChannelSubscription(
                user_id=user_id,
                channel_id=channel_id,
                amount_stars=price,
                expires_at=expires_at,
                auto_renew=auto_renew,
            )
            self.db.add(sub)
        self._credit_creator(
            channel.admin_user_id,
            price,
            tx_type="channel_subscription_received",
            reference_type="channel",
            reference_id=channel_id,
            counterparty_user_id=user_id,
        )
        _invalidate_user_feed_cache(self.db, user_id)
        self.db.flush()
        return sub

    def has_paid_channel_access(self, user_id: Optional[int], channel: Channel) -> bool:
        if not getattr(channel, "is_paid", False):
            return True
        if user_id is None:
            return False
        if channel.admin_user_id == user_id:
            return True
        now = datetime.utcnow()
        return (
            self.db.query(PaidChannelSubscription.id)
            .filter(
                PaidChannelSubscription.user_id == user_id,
                PaidChannelSubscription.channel_id == channel.id,
                PaidChannelSubscription.status == "active",
                PaidChannelSubscription.expires_at > now,
            )
            .first()
            is not None
        )

    def boost_post(self, user_id: int, post_id: int, amount: int, *, duration_days: int = 7) -> PostBoost:
        if duration_days < 1 or duration_days > 30:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Duration must be between 1 and 30 days")
        post = self.db.query(Post).filter(Post.id == post_id, Post.deleted_at.is_(None)).first()
        if not post:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Post not found")
        self._spend_stars(
            user_id,
            amount,
            tx_type="boost",
            reference_type="post",
            reference_id=post_id,
            counterparty_user_id=post.user_id,
        )
        post.is_promoted = True
        boost = PostBoost(
            post_id=post_id,
            buyer_id=user_id,
            amount_stars=amount,
            duration_days=duration_days,
            expires_at=datetime.utcnow() + timedelta(days=duration_days),
        )
        self.db.add(boost)
        _invalidate_user_feed_cache(self.db, user_id)
        _invalidate_user_feed_cache(self.db, post.user_id)
        self.db.flush()
        return boost

    def request_creator_payout(
        self,
        user_id: int,
        amount_stars: int,
        *,
        note: Optional[str] = None,
        stars_to_rub_rate: float = 0.8,
    ) -> CreatorPayoutRequest:
        if amount_stars <= 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Amount must be positive",
            )
        balance = self.creator_balance(user_id)
        available = int(balance.available_stars or 0)
        if amount_stars > available:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Not enough creator balance",
            )
        amount_rub = round(float(amount_stars) * float(stars_to_rub_rate), 2)
        payout = CreatorPayoutRequest(
            creator_user_id=user_id,
            amount_stars=amount_stars,
            amount_rub=amount_rub,
            status="pending",
            note=(note or "").strip() or None,
        )
        balance.available_stars = available - amount_stars
        balance.pending_stars = int(balance.pending_stars or 0) + amount_stars
        self.db.add(payout)
        self.db.flush()
        return payout

    def list_creator_payouts(self, user_id: int, *, limit: int = 50) -> list[CreatorPayoutRequest]:
        return (
            self.db.query(CreatorPayoutRequest)
            .filter(CreatorPayoutRequest.creator_user_id == user_id)
            .order_by(CreatorPayoutRequest.created_at.desc(), CreatorPayoutRequest.id.desc())
            .limit(max(1, min(limit, 200)))
            .all()
        )

    def review_payout(
        self,
        payout_id: int,
        *,
        reviewer_user_id: int,
        approve: bool,
        note: Optional[str] = None,
    ) -> CreatorPayoutRequest:
        payout = (
            self.db.query(CreatorPayoutRequest)
            .filter(CreatorPayoutRequest.id == payout_id)
            .first()
        )
        if not payout:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Payout not found")
        if payout.status != "pending":
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Payout already reviewed")
        payout.status = "approved" if approve else "rejected"
        payout.reviewed_by_user_id = reviewer_user_id
        payout.reviewed_at = datetime.utcnow()
        if note is not None:
            payout.note = note.strip() or payout.note
        creator_balance = self.creator_balance(payout.creator_user_id)
        if not approve:
            creator_balance.pending_stars = max(
                0, int(creator_balance.pending_stars or 0) - int(payout.amount_stars)
            )
            creator_balance.available_stars = int(creator_balance.available_stars or 0) + int(
                payout.amount_stars
            )
        self.db.flush()
        return payout

    def has_unlocked_message(self, user_id: Optional[int], message: Message) -> bool:
        if not getattr(message, "is_paid", False):
            return True
        if user_id is None:
            return False
        if message.sender_id == user_id:
            return True
        return (
            self.db.query(PaidMessageUnlock.id)
            .filter(
                PaidMessageUnlock.user_id == user_id,
                PaidMessageUnlock.message_id == message.id,
                PaidMessageUnlock.status == "completed",
            )
            .first()
            is not None
        )

    def purchase_message(
        self,
        user_id: int,
        message_id: int,
        *,
        idempotency_key: Optional[str] = None,
    ) -> PaidMessageUnlock:
        message = (
            self.db.query(Message)
            .filter(Message.id == message_id, Message.deleted_at.is_(None))
            .first()
        )
        if not message:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Message not found")
        if not getattr(message, "is_paid", False):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Message is not paid")
        member = (
            self.db.query(ConversationMember.id)
            .filter(
                ConversationMember.conversation_id == message.conversation_id,
                ConversationMember.user_id == user_id,
            )
            .first()
        )
        if not member:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")
        if message.sender_id == user_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Authors already own their media",
            )
        existing = (
            self.db.query(PaidMessageUnlock)
            .filter(
                PaidMessageUnlock.user_id == user_id,
                PaidMessageUnlock.message_id == message_id,
            )
            .first()
        )
        if existing:
            return existing
        amount = int(getattr(message, "price_stars", 0) or 0)
        if amount <= 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Paid media price must be greater than 0 stars",
            )
        self._spend_stars(
            user_id,
            amount,
            tx_type="paid_media_purchase",
            reference_type="message",
            reference_id=message_id,
            counterparty_user_id=message.sender_id,
            idempotency_key=idempotency_key,
        )
        unlock = PaidMessageUnlock(
            user_id=user_id,
            message_id=message_id,
            author_id=message.sender_id,
            amount_stars=amount,
        )
        self.db.add(unlock)
        self._credit_creator(
            message.sender_id,
            amount,
            tx_type="paid_media_sale",
            reference_type="message",
            reference_id=message_id,
            counterparty_user_id=user_id,
        )
        self.db.flush()
        return unlock

    def charge_paid_message_fee(
        self,
        sender_id: int,
        recipient_id: int,
        *,
        conversation_id: int,
        message_id: int,
    ) -> Optional[StarTransaction]:
        """Charge Stars to send a DM when recipient has paid_message_stars > 0."""
        if sender_id == recipient_id:
            return None
        recipient = (
            self.db.query(User)
            .filter(User.id == recipient_id, User.deleted_at.is_(None))
            .first()
        )
        if not recipient:
            return None
        amount = int(getattr(recipient, "paid_message_stars", 0) or 0)
        if amount <= 0:
            return None
        tx = self._spend_stars(
            sender_id,
            amount,
            tx_type="paid_message",
            reference_type="message",
            reference_id=message_id,
            counterparty_user_id=recipient_id,
            meta={"conversation_id": conversation_id},
        )
        self._credit_creator(
            recipient_id,
            amount,
            tx_type="paid_message_received",
            reference_type="message",
            reference_id=message_id,
            counterparty_user_id=sender_id,
            meta={"conversation_id": conversation_id},
        )
        return tx

    def list_star_gifts(self) -> list[StarGift]:
        return (
            self.db.query(StarGift)
            .filter(StarGift.is_active.is_(True))
            .order_by(StarGift.sort_order.asc(), StarGift.id.asc())
            .all()
        )

    def send_star_gift(
        self,
        sender_id: int,
        *,
        gift_id: int,
        conversation_id: int,
        message: Optional[str] = None,
    ) -> Message:
        gift = (
            self.db.query(StarGift)
            .filter(StarGift.id == gift_id, StarGift.is_active.is_(True))
            .first()
        )
        if not gift:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Gift not found")
        member = (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == sender_id,
            )
            .first()
        )
        if not member:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")
        conv = self.db.query(Conversation).filter(Conversation.id == conversation_id).first()
        if not conv:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Chat not found")
        if conv.type != "direct":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Gifts can only be sent in direct chats",
            )
        recipient_id = (
            conv.direct_user_high_id
            if conv.direct_user_low_id == sender_id
            else conv.direct_user_low_id
        )
        if not recipient_id or recipient_id == sender_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Gift recipient not found",
            )

        import json as _json

        note = (message or "").strip()
        content = _json.dumps(
            {
                "gift_id": gift.id,
                "slug": gift.slug,
                "title": gift.title,
                "emoji": gift.emoji,
                "stars": gift.stars,
                "message": note or None,
            },
            ensure_ascii=False,
        )
        msg = Message(
            conversation_id=conversation_id,
            sender_id=sender_id,
            type="gift",
            content=content,
            media_url=None,
        )
        self.db.add(msg)
        self.db.flush()

        self._spend_stars(
            sender_id,
            int(gift.stars),
            tx_type="gift",
            reference_type="message",
            reference_id=msg.id,
            counterparty_user_id=recipient_id,
            meta={"gift_id": gift.id, "slug": gift.slug},
        )
        self._credit_creator(
            recipient_id,
            int(gift.stars),
            tx_type="gift_received",
            reference_type="message",
            reference_id=msg.id,
            counterparty_user_id=sender_id,
            meta={"gift_id": gift.id, "slug": gift.slug},
        )
        conv.updated_at = datetime.utcnow()
        self.db.flush()
        return msg

    def pay_for_reaction(
        self,
        user_id: int,
        *,
        message: Message,
        amount_stars: int,
    ) -> None:
        if amount_stars <= 0:
            return
        if message.sender_id == user_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot pay reaction on your own message",
            )
        self._spend_stars(
            user_id,
            amount_stars,
            tx_type="paid_reaction",
            reference_type="message",
            reference_id=message.id,
            counterparty_user_id=message.sender_id,
        )
        self._credit_creator(
            message.sender_id,
            amount_stars,
            tx_type="paid_reaction_received",
            reference_type="message",
            reference_id=message.id,
            counterparty_user_id=user_id,
        )


def expire_due_post_boosts(db: Session) -> int:
    now = datetime.utcnow()
    expired = (
        db.query(PostBoost)
        .filter(
            PostBoost.status == "active",
            PostBoost.expires_at.isnot(None),
            PostBoost.expires_at <= now,
        )
        .limit(100)
        .all()
    )
    if not expired:
        return 0
    post_ids = {b.post_id for b in expired}
    for boost in expired:
        boost.status = "expired"
    for post_id in post_ids:
        still_active = (
            db.query(PostBoost.id)
            .filter(
                PostBoost.post_id == post_id,
                PostBoost.status == "active",
                PostBoost.expires_at > now,
            )
            .first()
            is not None
        )
        if not still_active:
            post = db.query(Post).filter(Post.id == post_id).first()
            if post:
                post.is_promoted = False
    return len(expired)

