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
    PaidMessageException,
    PaidMessageUnlock,
    PostBoost,
    StarGift,
    StarTransaction,
    UserStarGift,
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
        # Cashout ledger cannot exceed remaining spendable Stars.
        # Do not subtract purchased top-ups from creator available earnings.
        balance = (
            self.db.query(CreatorBalance)
            .filter(CreatorBalance.user_id == user_id)
            .with_for_update()
            .first()
        )
        if balance is not None:
            spendable = self.star_balance(user_id)
            available = int(balance.available_stars or 0)
            if available > spendable:
                balance.available_stars = max(0, spendable)
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
        # Paying for a private channel grants active membership (Telegram-like).
        # Fail the whole subscribe if membership cannot be granted — otherwise
        # Stars are spent but posts stay locked.
        from app.models.community_member import ChannelMember
        from app.services.channel_membership_service import (
            MEMBER_STATUS_ACTIVE,
            sync_channel_members_count,
        )

        member = (
            self.db.query(ChannelMember)
            .filter(
                ChannelMember.channel_id == channel_id,
                ChannelMember.user_id == user_id,
            )
            .first()
        )
        if member is None:
            self.db.add(
                ChannelMember(
                    channel_id=channel_id,
                    user_id=user_id,
                    role="member",
                    status=MEMBER_STATUS_ACTIVE,
                )
            )
            sync_channel_members_count(self.db, channel_id)
        elif member.status != MEMBER_STATUS_ACTIVE:
            member.status = MEMBER_STATUS_ACTIVE
            sync_channel_members_count(self.db, channel_id)
        _invalidate_user_feed_cache(self.db, user_id)
        self.db.flush()
        return sub

    def get_channel_subscription(
        self, user_id: int, channel_id: int
    ) -> Optional[PaidChannelSubscription]:
        return (
            self.db.query(PaidChannelSubscription)
            .filter(
                PaidChannelSubscription.user_id == user_id,
                PaidChannelSubscription.channel_id == channel_id,
            )
            .first()
        )

    def update_channel_subscription_auto_renew(
        self, user_id: int, channel_id: int, *, auto_renew: bool
    ) -> PaidChannelSubscription:
        sub = self.get_channel_subscription(user_id, channel_id)
        if sub is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="Subscription not found"
            )
        now = datetime.utcnow()
        if sub.status != "active" or not sub.expires_at or sub.expires_at <= now:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Subscription is not active",
            )
        sub.auto_renew = bool(auto_renew)
        self.db.flush()
        return sub

    def cancel_channel_subscription(
        self, user_id: int, channel_id: int
    ) -> PaidChannelSubscription:
        """Cancel auto-renew; access remains until expires_at (Telegram-like)."""
        sub = self.get_channel_subscription(user_id, channel_id)
        if sub is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="Subscription not found"
            )
        now = datetime.utcnow()
        if sub.status != "active" or not sub.expires_at or sub.expires_at <= now:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Subscription is not active",
            )
        sub.auto_renew = False
        self.db.flush()
        return sub

    def list_paid_message_exceptions(self, owner_id: int) -> list[User]:
        rows = (
            self.db.query(User)
            .join(
                PaidMessageException,
                PaidMessageException.allowed_user_id == User.id,
            )
            .filter(
                PaidMessageException.owner_id == owner_id,
                User.deleted_at.is_(None),
            )
            .order_by(PaidMessageException.created_at.desc(), User.id.asc())
            .all()
        )
        return rows

    def add_paid_message_exception(
        self, owner_id: int, allowed_user_id: int
    ) -> User:
        if owner_id == allowed_user_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot add yourself as exception",
            )
        allowed = (
            self.db.query(User)
            .filter(User.id == allowed_user_id, User.deleted_at.is_(None))
            .first()
        )
        if not allowed:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="User not found"
            )
        existing = (
            self.db.query(PaidMessageException)
            .filter(
                PaidMessageException.owner_id == owner_id,
                PaidMessageException.allowed_user_id == allowed_user_id,
            )
            .first()
        )
        if existing is None:
            self.db.add(
                PaidMessageException(
                    owner_id=owner_id, allowed_user_id=allowed_user_id
                )
            )
            self.db.flush()
        return allowed

    def remove_paid_message_exception(
        self, owner_id: int, allowed_user_id: int
    ) -> None:
        row = (
            self.db.query(PaidMessageException)
            .filter(
                PaidMessageException.owner_id == owner_id,
                PaidMessageException.allowed_user_id == allowed_user_id,
            )
            .first()
        )
        if row is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="Exception not found"
            )
        self.db.delete(row)
        self.db.flush()

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
        # Escrow spendable Stars immediately so cashout can't be spent twice
        # while the request is pending.
        if self.star_balance(user_id) < amount_stars:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Not enough spendable stars to cash out",
            )
        amount_rub = round(float(amount_stars) * float(stars_to_rub_rate), 2)
        payout = CreatorPayoutRequest(
            creator_user_id=user_id,
            amount_stars=amount_stars,
            amount_rub=amount_rub,
            status="pending",
            note=(note or "").strip() or None,
        )
        self.db.add(payout)
        self.db.flush()
        self._spend_stars(
            user_id,
            amount_stars,
            tx_type="payout_hold",
            reference_type="payout",
            reference_id=payout.id,
        )
        balance.available_stars = available - amount_stars
        balance.pending_stars = int(balance.pending_stars or 0) + amount_stars
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
        amount = int(payout.amount_stars)
        if not approve:
            creator_balance.pending_stars = max(
                0, int(creator_balance.pending_stars or 0) - amount
            )
            creator_balance.available_stars = int(creator_balance.available_stars or 0) + amount
            # Release escrowed spendable Stars.
            self.db.add(
                StarTransaction(
                    user_id=payout.creator_user_id,
                    amount=amount,
                    type="payout_refund",
                    reference_type="payout",
                    reference_id=payout.id,
                    status="completed",
                )
            )
        else:
            creator_balance.pending_stars = max(
                0, int(creator_balance.pending_stars or 0) - amount
            )
            creator_balance.paid_out_stars = int(creator_balance.paid_out_stars or 0) + amount
            payout.status = "paid"
            payout.paid_at = datetime.utcnow()
            # Spendable Stars were already escrowed on request (payout_hold).
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

        # Album: one Stars charge unlocks every paid item in the media group.
        group_id = (getattr(message, "media_group_id", None) or "").strip()
        album_messages = [message]
        if group_id:
            album_messages = (
                self.db.query(Message)
                .filter(
                    Message.conversation_id == message.conversation_id,
                    Message.media_group_id == group_id,
                    Message.deleted_at.is_(None),
                    Message.is_paid.is_(True),
                )
                .order_by(Message.id.asc())
                .all()
            ) or [message]

        already_unlocked_ids = {
            int(row[0])
            for row in self.db.query(PaidMessageUnlock.message_id)
            .filter(
                PaidMessageUnlock.user_id == user_id,
                PaidMessageUnlock.message_id.in_([m.id for m in album_messages]),
                PaidMessageUnlock.status == "completed",
            )
            .all()
        }
        to_unlock = [m for m in album_messages if m.id not in already_unlocked_ids]
        if not to_unlock:
            # All album items already unlocked — return the original row if any.
            return (
                self.db.query(PaidMessageUnlock)
                .filter(
                    PaidMessageUnlock.user_id == user_id,
                    PaidMessageUnlock.message_id == message_id,
                )
                .first()
            ) or PaidMessageUnlock(
                user_id=user_id,
                message_id=message_id,
                author_id=message.sender_id,
                amount_stars=0,
                status="completed",
            )

        amount = max(int(getattr(m, "price_stars", 0) or 0) for m in to_unlock)
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
            meta={"media_group_id": group_id or None, "unlocked_count": len(to_unlock)},
        )
        unlock: Optional[PaidMessageUnlock] = None
        for m in to_unlock:
            row = PaidMessageUnlock(
                user_id=user_id,
                message_id=m.id,
                author_id=m.sender_id,
                amount_stars=amount if m.id == message_id else 0,
            )
            self.db.add(row)
            if m.id == message_id:
                unlock = row
        if unlock is None:
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
            meta={"media_group_id": group_id or None, "unlocked_count": len(to_unlock)},
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
        media_group_id: Optional[str] = None,
    ) -> Optional[StarTransaction]:
        """Charge Stars to send a DM when recipient has paid_message_stars > 0.

        Album sends share one media_group_id — charge once for the whole album.
        """
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
        # Telegram-like exceptions: allowlisted senders skip the fee.
        exempt = (
            self.db.query(PaidMessageException.id)
            .filter(
                PaidMessageException.owner_id == recipient_id,
                PaidMessageException.allowed_user_id == sender_id,
            )
            .first()
        )
        if exempt is not None:
            return None
        group_id = (media_group_id or "").strip() or None
        ref_type = "media_group" if group_id else "message"
        ref_id = conversation_id if group_id else message_id
        idem = (
            f"paid_dm:album:{conversation_id}:{group_id}:{sender_id}"
            if group_id
            else f"paid_dm:msg:{message_id}:{sender_id}"
        )
        existing = (
            self.db.query(StarTransaction)
            .filter(StarTransaction.idempotency_key == idem)
            .first()
        )
        if existing is not None:
            return existing
        tx = self._spend_stars(
            sender_id,
            amount,
            tx_type="paid_message",
            reference_type=ref_type,
            reference_id=ref_id,
            counterparty_user_id=recipient_id,
            idempotency_key=idem,
            meta={
                "conversation_id": conversation_id,
                "message_id": message_id,
                "media_group_id": group_id,
            },
        )
        self._credit_creator(
            recipient_id,
            amount,
            tx_type="paid_message_received",
            reference_type=ref_type,
            reference_id=ref_id,
            counterparty_user_id=sender_id,
            meta={
                "conversation_id": conversation_id,
                "message_id": message_id,
                "media_group_id": group_id,
            },
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
        idempotency_key: Optional[str] = None,
    ) -> Message:
        gift = (
            self.db.query(StarGift)
            .filter(StarGift.id == gift_id, StarGift.is_active.is_(True))
            .first()
        )
        if not gift:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Gift not found")
        idem = (idempotency_key or "").strip() or None
        if idem:
            existing_tx = (
                self.db.query(StarTransaction)
                .filter(StarTransaction.idempotency_key == idem)
                .first()
            )
            if existing_tx is not None and existing_tx.reference_id:
                existing_msg = (
                    self.db.query(Message)
                    .filter(Message.id == int(existing_tx.reference_id))
                    .first()
                )
                if existing_msg is not None:
                    return existing_msg
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

        # Fail fast before creating a gift message.
        if self.star_balance(sender_id) < int(gift.stars):
            raise HTTPException(
                status_code=status.HTTP_402_PAYMENT_REQUIRED,
                detail={"code": "STARS_REQUIRED", "message": "Недостаточно звёзд"},
            )

        import json as _json

        note = (message or "").strip()
        # Create message first so we can bind inventory + spend idempotently.
        msg = Message(
            conversation_id=conversation_id,
            sender_id=sender_id,
            type="gift",
            content="{}",
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
            idempotency_key=idem or f"gift:msg:{msg.id}",
            meta={"gift_id": gift.id, "slug": gift.slug},
        )
        # Telegram-like: Stars sit in the gift until the recipient converts.
        owned = UserStarGift(
            owner_id=recipient_id,
            sender_id=sender_id,
            gift_id=gift.id,
            message_id=msg.id,
            stars=int(gift.stars),
            slug=gift.slug,
            title=gift.title,
            emoji=gift.emoji,
            note=note or None,
            status="held",
            is_displayed=True,
        )
        self.db.add(owned)
        self.db.flush()
        msg.content = _json.dumps(
            {
                "gift_id": gift.id,
                "user_gift_id": owned.id,
                "slug": gift.slug,
                "title": gift.title,
                "emoji": gift.emoji,
                "stars": gift.stars,
                "message": note or None,
                "status": "held",
            },
            ensure_ascii=False,
        )
        conv.updated_at = datetime.utcnow()
        self.db.flush()
        return msg

    def list_user_star_gifts(
        self,
        owner_id: int,
        *,
        displayed_only: bool = False,
        include_converted: bool = False,
        limit: int = 50,
    ) -> list[UserStarGift]:
        limit = max(1, min(int(limit or 50), 100))
        q = self.db.query(UserStarGift).filter(UserStarGift.owner_id == owner_id)
        if displayed_only:
            q = q.filter(
                UserStarGift.is_displayed.is_(True),
                UserStarGift.status.in_(("held", "kept")),
            )
        elif not include_converted:
            q = q.filter(UserStarGift.status.in_(("held", "kept")))
        return (
            q.order_by(UserStarGift.created_at.desc(), UserStarGift.id.desc())
            .limit(limit)
            .all()
        )

    def convert_user_star_gift(self, owner_id: int, user_gift_id: int) -> UserStarGift:
        gift = (
            self.db.query(UserStarGift)
            .filter(UserStarGift.id == user_gift_id, UserStarGift.owner_id == owner_id)
            .with_for_update()
            .first()
        )
        if not gift:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Gift not found")
        if gift.status == "converted":
            return gift
        if gift.status not in ("held", "kept"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Gift cannot be converted"
            )
        amount = int(gift.stars)
        self.add_stars(
            owner_id,
            amount,
            tx_type="gift_converted",
            idempotency_key=f"gift_convert:{gift.id}",
            meta={
                "user_gift_id": gift.id,
                "gift_id": gift.gift_id,
                "slug": gift.slug,
                "from_sender_id": gift.sender_id,
            },
        )
        # Creator earnings ledger tracks converted gift value too.
        balance = self.creator_balance(owner_id)
        balance.available_stars = int(balance.available_stars or 0) + amount
        gift.status = "converted"
        gift.is_displayed = False
        gift.converted_at = datetime.utcnow()
        self._patch_gift_message_status(gift, status="converted")
        self.db.flush()
        return gift

    def keep_user_star_gift(self, owner_id: int, user_gift_id: int) -> UserStarGift:
        gift = (
            self.db.query(UserStarGift)
            .filter(UserStarGift.id == user_gift_id, UserStarGift.owner_id == owner_id)
            .with_for_update()
            .first()
        )
        if not gift:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Gift not found")
        if gift.status == "converted":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Gift already converted"
            )
        gift.status = "kept"
        gift.is_displayed = True
        self._patch_gift_message_status(gift, status="kept")
        self.db.flush()
        return gift

    def set_user_star_gift_displayed(
        self, owner_id: int, user_gift_id: int, *, displayed: bool
    ) -> UserStarGift:
        gift = (
            self.db.query(UserStarGift)
            .filter(UserStarGift.id == user_gift_id, UserStarGift.owner_id == owner_id)
            .with_for_update()
            .first()
        )
        if not gift:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Gift not found")
        if gift.status == "converted":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Converted gifts cannot be displayed",
            )
        gift.is_displayed = bool(displayed)
        if displayed and gift.status == "held":
            gift.status = "kept"
        self.db.flush()
        return gift

    def _patch_gift_message_status(self, gift: UserStarGift, *, status: str) -> None:
        if not gift.message_id:
            return
        import json as _json

        msg = self.db.query(Message).filter(Message.id == gift.message_id).first()
        if not msg or msg.type != "gift":
            return
        try:
            payload = _json.loads(msg.content or "{}")
            if not isinstance(payload, dict):
                payload = {}
        except Exception:
            payload = {}
        payload["status"] = status
        payload["user_gift_id"] = gift.id
        msg.content = _json.dumps(payload, ensure_ascii=False)

    def pay_for_reaction(
        self,
        user_id: int,
        *,
        message: Message,
        amount_stars: int,
        idempotency_key: Optional[str] = None,
    ) -> None:
        if amount_stars <= 0:
            return
        if message.sender_id == user_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot pay reaction on your own message",
            )
        idem = (idempotency_key or "").strip() or None
        if idem:
            existing = (
                self.db.query(StarTransaction.id)
                .filter(StarTransaction.idempotency_key == idem)
                .first()
            )
            if existing is not None:
                return
        self._spend_stars(
            user_id,
            amount_stars,
            tx_type="paid_reaction",
            reference_type="message",
            reference_id=message.id,
            counterparty_user_id=message.sender_id,
            idempotency_key=idem,
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


def _revoke_paid_channel_membership(db: Session, *, user_id: int, channel_id: int) -> None:
    """Remove paid-subscriber membership so feed/posts lock after expiry."""
    from app.models.community_member import ChannelMember
    from app.services.channel_membership_service import sync_channel_members_count

    member = (
        db.query(ChannelMember)
        .filter(
            ChannelMember.channel_id == channel_id,
            ChannelMember.user_id == user_id,
        )
        .first()
    )
    if member is None:
        return
    if member.role in ("owner", "admin"):
        return
    db.delete(member)
    sync_channel_members_count(db, channel_id)
    _invalidate_user_feed_cache(db, user_id)


def expire_due_channel_subscriptions(db: Session) -> int:
    """Mark expired paid channel subscriptions; optionally auto-renew once."""
    now = datetime.utcnow()
    due = (
        db.query(PaidChannelSubscription)
        .filter(
            PaidChannelSubscription.status == "active",
            PaidChannelSubscription.expires_at.isnot(None),
            PaidChannelSubscription.expires_at <= now,
        )
        .limit(100)
        .all()
    )
    if not due:
        return 0
    service = PaidFeaturesService(db)
    changed = 0
    for sub in due:
        renewed = False
        if sub.auto_renew:
            try:
                service.subscribe_channel(
                    sub.user_id,
                    sub.channel_id,
                    months=1,
                    auto_renew=True,
                )
                renewed = True
                changed += 1
            except Exception:
                # Calendar already expired — fail closed (revoke access).
                renewed = False
        if renewed:
            continue
        sub.status = "expired"
        _revoke_paid_channel_membership(
            db, user_id=sub.user_id, channel_id=sub.channel_id
        )
        changed += 1
    return changed

