"""Business logic for Telegram-like paid features."""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Optional

from fastapi import HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.community import Channel
from app.models.paid_features import (
    CreatorBalance,
    PaidChannelSubscription,
    PaidContentPurchase,
    PostBoost,
    StarTransaction,
)
from app.models.post import Post


class PaidFeaturesService:
    def __init__(self, db: Session):
        self.db = db

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
                return existing
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
        self.db.flush()
        return purchase

    def donate(self, sender_id: int, recipient_id: int, amount: int, *, message: Optional[str] = None) -> StarTransaction:
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

    def subscribe_channel(self, user_id: int, channel_id: int, *, months: int = 1) -> PaidChannelSubscription:
        channel = self.db.query(Channel).filter(Channel.id == channel_id).first()
        if not channel:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Channel not found")
        if channel.admin_user_id == user_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Owner already has access")
        price = int(getattr(channel, "monthly_price_stars", 0) or 0) * max(1, months)
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
        expires_at = expires_base + timedelta(days=30 * max(1, months))
        if existing:
            existing.amount_stars = price
            existing.status = "active"
            existing.expires_at = expires_at
            sub = existing
        else:
            sub = PaidChannelSubscription(
                user_id=user_id,
                channel_id=channel_id,
                amount_stars=price,
                expires_at=expires_at,
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
            expires_at=datetime.utcnow() + timedelta(days=max(1, duration_days)),
        )
        self.db.add(boost)
        self.db.flush()
        return boost


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

