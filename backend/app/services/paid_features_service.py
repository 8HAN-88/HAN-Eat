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
    ChannelSuggestedPost,
    CreatorPayoutRequest,
    CreatorBalance,
    PaidChannelSubscription,
    PaidGroupSubscription,
    PaidContentPurchase,
    PaidMessageException,
    PaidMessageUnlock,
    PostBoost,
    StarGift,
    StarGiveaway,
    StarGiveawayParticipant,
    StarInvoice,
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

    def donate(
        self,
        sender_id: int,
        recipient_id: int,
        amount: int,
        *,
        message: Optional[str] = None,
        create_chat_message: bool = True,
    ) -> tuple[StarTransaction, Optional[Message]]:
        """Send Stars tip. Optionally posts a Telegram-like tip bubble in the DM."""
        if sender_id == recipient_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot donate to yourself")
        recipient_exists = self.db.query(User.id).filter(User.id == recipient_id, User.deleted_at.is_(None)).first()
        if not recipient_exists:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recipient not found")
        note = (message or "").strip() or None
        from app.services.emoji_pack_service import EmojiPackService

        EmojiPackService(self.db).require_send_tokens_http(sender_id, note)
        tx = self._spend_stars(
            sender_id,
            amount,
            tx_type="donation",
            reference_type="user",
            reference_id=recipient_id,
            counterparty_user_id=recipient_id,
            meta={"message": note} if note else None,
        )
        self._credit_creator(
            recipient_id,
            amount,
            tx_type="donation_received",
            reference_type="user",
            reference_id=sender_id,
            counterparty_user_id=sender_id,
            meta={"message": note} if note else None,
        )
        tip_msg: Optional[Message] = None
        if create_chat_message:
            tip_msg = self._create_stars_tip_message(
                sender_id,
                recipient_id,
                amount=amount,
                note=note,
            )
        return tx, tip_msg

    def _create_stars_tip_message(
        self,
        sender_id: int,
        recipient_id: int,
        *,
        amount: int,
        note: Optional[str],
    ) -> Optional[Message]:
        """Best-effort tip bubble in the direct chat (skip if blocked / unavailable)."""
        import json as _json

        from app.services.chat_service import ChatService

        try:
            conv = ChatService(self.db).get_or_create_direct(sender_id, recipient_id)
        except ValueError:
            return None
        except Exception:
            return None
        tip_msg = Message(
            conversation_id=conv.id,
            sender_id=sender_id,
            type="stars_tip",
            content=_json.dumps(
                {
                    "amount": int(amount),
                    "message": note,
                },
                ensure_ascii=False,
            ),
            media_url=None,
        )
        self.db.add(tip_msg)
        self.db.flush()
        conv.updated_at = datetime.utcnow()
        self.db.flush()
        return tip_msg

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

    def set_group_paid_settings(
        self,
        actor_user_id: int,
        conversation_id: int,
        *,
        is_paid: bool,
        monthly_price_stars: int,
    ) -> Conversation:
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id, Conversation.type == "group")
            .first()
        )
        if not conv:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found")
        member = (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == actor_user_id,
            )
            .first()
        )
        is_owner = conv.created_by_user_id == actor_user_id
        if not is_owner and not (member and member.is_admin and member.can_change_info):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not group admin")
        price = max(0, int(monthly_price_stars or 0))
        if is_paid and (price < 10 or price > 100_000):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Monthly price must be between 10 and 100000 stars",
            )
        conv.is_paid = bool(is_paid) and price > 0
        conv.monthly_price_stars = price if conv.is_paid else 0
        self.db.flush()
        return conv

    def get_group_subscription(
        self, user_id: int, conversation_id: int
    ) -> Optional[PaidGroupSubscription]:
        return (
            self.db.query(PaidGroupSubscription)
            .filter(
                PaidGroupSubscription.user_id == user_id,
                PaidGroupSubscription.conversation_id == conversation_id,
            )
            .first()
        )

    def has_active_group_subscription(self, user_id: int, conversation_id: int) -> bool:
        now = datetime.utcnow()
        sub = self.get_group_subscription(user_id, conversation_id)
        return bool(
            sub
            and sub.status == "active"
            and sub.expires_at
            and sub.expires_at > now
        )

    def assert_can_join_paid_group(self, user_id: int, conv: Conversation) -> None:
        if not bool(getattr(conv, "is_paid", False)):
            return
        price = int(getattr(conv, "monthly_price_stars", 0) or 0)
        if price <= 0:
            return
        if conv.created_by_user_id == user_id:
            return
        if self.has_active_group_subscription(user_id, conv.id):
            return
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail={
                "code": "group_paid_required",
                "conversation_id": conv.id,
                "monthly_price_stars": price,
                "title": conv.title,
            },
        )

    def subscribe_group(
        self,
        user_id: int,
        conversation_id: int,
        *,
        months: int = 1,
        auto_renew: bool = False,
    ) -> PaidGroupSubscription:
        if months < 1 or months > 12:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Months must be between 1 and 12",
            )
        conv = (
            self.db.query(Conversation)
            .filter(Conversation.id == conversation_id, Conversation.type == "group")
            .first()
        )
        if not conv:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found")
        if conv.created_by_user_id == user_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Owner already has access"
            )
        price = int(getattr(conv, "monthly_price_stars", 0) or 0) * months
        if not getattr(conv, "is_paid", False) or price <= 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Group is not paid"
            )
        owner_id = int(conv.created_by_user_id or 0)
        now = datetime.utcnow()
        existing = self.get_group_subscription(user_id, conversation_id)
        self._spend_stars(
            user_id,
            price,
            tx_type="group_subscription",
            reference_type="conversation",
            reference_id=conversation_id,
            counterparty_user_id=owner_id or None,
        )
        expires_base = (
            existing.expires_at
            if existing and existing.expires_at and existing.expires_at > now
            else now
        )
        expires_at = expires_base + timedelta(days=30 * months)
        if existing:
            existing.amount_stars = price
            existing.status = "active"
            existing.expires_at = expires_at
            existing.auto_renew = auto_renew
            sub = existing
        else:
            sub = PaidGroupSubscription(
                user_id=user_id,
                conversation_id=conversation_id,
                amount_stars=price,
                expires_at=expires_at,
                auto_renew=auto_renew,
            )
            self.db.add(sub)
        if owner_id:
            self._credit_creator(
                owner_id,
                price,
                tx_type="group_subscription_received",
                reference_type="conversation",
                reference_id=conversation_id,
                counterparty_user_id=user_id,
            )
        member = (
            self.db.query(ConversationMember)
            .filter(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == user_id,
            )
            .first()
        )
        if member is None:
            self.db.add(ConversationMember(conversation_id=conversation_id, user_id=user_id))
        self.db.flush()
        return sub

    def set_ton_address(self, user_id: int, ton_address: Optional[str]) -> User:
        user = self.db.query(User).filter(User.id == user_id, User.deleted_at.is_(None)).first()
        if not user:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
        clean = (ton_address or "").strip()
        if not clean:
            user.ton_address = None
            self.db.flush()
            return user
        if len(clean) < 10 or len(clean) > 128:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid TON address"
            )
        user.ton_address = clean
        self.db.flush()
        return user

    def reorder_user_star_gifts(self, owner_id: int, gift_ids: list[int]) -> list[UserStarGift]:
        ids = [int(x) for x in gift_ids if int(x) > 0]
        if not ids:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Empty order")
        gifts = (
            self.db.query(UserStarGift)
            .filter(UserStarGift.owner_id == owner_id, UserStarGift.id.in_(ids))
            .all()
        )
        by_id = {g.id: g for g in gifts}
        if len(by_id) != len(set(ids)):
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Gift not found")
        for index, gift_id in enumerate(ids):
            by_id[gift_id].display_order = index
        self.db.flush()
        return self.list_user_star_gifts(owner_id)

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
        method: str = "rub",
        ton_address: Optional[str] = None,
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
        kind = (method or "rub").strip().lower()
        if kind not in ("rub", "ton"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid payout method"
            )
        dest = (ton_address or "").strip()
        if kind == "ton":
            user = self.db.query(User).filter(User.id == user_id).first()
            dest = dest or (getattr(user, "ton_address", None) or "").strip()
            if len(dest) < 10:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="TON address required",
                )
        amount_rub = round(float(amount_stars) * float(stars_to_rub_rate), 2)
        payout = CreatorPayoutRequest(
            creator_user_id=user_id,
            amount_stars=amount_stars,
            amount_rub=amount_rub,
            status="pending",
            note=(note or "").strip() or None,
            method=kind,
            ton_address=dest or None,
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
        hide_name: bool = False,
        idempotency_key: Optional[str] = None,
    ) -> Message:
        gift = (
            self.db.query(StarGift)
            .filter(StarGift.id == gift_id, StarGift.is_active.is_(True))
            .with_for_update()
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

        is_collectible = bool(getattr(gift, "is_limited", False))
        serial = None
        if is_collectible:
            sold = int(getattr(gift, "sold_count", 0) or 0)
            supply = getattr(gift, "total_supply", None)
            if supply is not None and sold >= int(supply):
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail={
                        "code": "GIFT_SOLD_OUT",
                        "message": "Лимитированный подарок распродан",
                    },
                )
            serial = sold + 1

        # Fail fast before creating a gift message.
        if self.star_balance(sender_id) < int(gift.stars):
            raise HTTPException(
                status_code=status.HTTP_402_PAYMENT_REQUIRED,
                detail={"code": "STARS_REQUIRED", "message": "Недостаточно звёзд"},
            )

        import json as _json

        note = (message or "").strip()
        from app.services.emoji_pack_service import EmojiPackService

        EmojiPackService(self.db).require_send_tokens_http(sender_id, note)
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
            meta={
                "gift_id": gift.id,
                "slug": gift.slug,
                "is_collectible": is_collectible,
                "serial": serial,
            },
        )
        if is_collectible:
            gift.sold_count = int(gift.sold_count or 0) + 1
        # Telegram-like: Stars sit in the gift until the recipient converts
        # (collectibles cannot be converted — kept as unique items).
        anonymous = bool(hide_name)
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
            status="kept" if is_collectible else "held",
            is_displayed=True,
            is_collectible=is_collectible,
            is_anonymous=anonymous,
            serial=serial,
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
                "status": owned.status,
                "is_collectible": is_collectible,
                "is_anonymous": anonymous,
                "serial": serial,
                "total_supply": getattr(gift, "total_supply", None),
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
            q.order_by(
                UserStarGift.display_order.asc(),
                UserStarGift.created_at.desc(),
                UserStarGift.id.desc(),
            )
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
        if bool(getattr(gift, "is_collectible", False)):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Collectible gifts cannot be converted to Stars",
            )
        if int(getattr(gift, "listed_stars", 0) or 0) > 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Take the gift off sale before converting",
            )
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

    def upgrade_user_star_gift(self, owner_id: int, user_gift_id: int) -> UserStarGift:
        """Pay upgrade_stars to turn a regular gift into a numbered collectible."""
        owned = (
            self.db.query(UserStarGift)
            .filter(UserStarGift.id == user_gift_id, UserStarGift.owner_id == owner_id)
            .with_for_update()
            .first()
        )
        if not owned:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Gift not found")
        if owned.status not in ("held", "kept"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Gift cannot be upgraded"
            )
        if bool(getattr(owned, "is_collectible", False)):
            return owned
        if int(getattr(owned, "listed_stars", 0) or 0) > 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Take the gift off sale before upgrading",
            )
        if not owned.gift_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Gift catalog entry missing"
            )
        catalog = (
            self.db.query(StarGift)
            .filter(StarGift.id == owned.gift_id)
            .with_for_update()
            .first()
        )
        if not catalog:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Gift not found")
        fee = int(getattr(catalog, "upgrade_stars", 0) or 0)
        if fee <= 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="This gift cannot be upgraded",
            )
        supply = getattr(catalog, "total_supply", None)
        sold = int(getattr(catalog, "sold_count", 0) or 0)
        # If catalog becomes limited via upgrade pool, enforce supply when set.
        if supply is not None and sold >= int(supply):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "code": "GIFT_SOLD_OUT",
                    "message": "Лимит коллекционных экземпляров исчерпан",
                },
            )
        self._spend_stars(
            owner_id,
            fee,
            tx_type="gift_upgrade",
            reference_type="user_gift",
            reference_id=owned.id,
            counterparty_user_id=None,
            idempotency_key=f"gift_upgrade:{owned.id}",
            meta={"gift_id": catalog.id, "slug": catalog.slug},
        )
        serial = sold + 1
        catalog.sold_count = sold + 1
        if not bool(getattr(catalog, "is_limited", False)):
            catalog.is_limited = True
        owned.is_collectible = True
        owned.serial = serial
        owned.status = "kept"
        owned.is_displayed = True
        self._patch_gift_message_status(
            owned,
            status="kept",
            extra={"is_collectible": True, "serial": serial},
        )
        self.db.flush()
        return owned

    def transfer_user_star_gift(
        self,
        owner_id: int,
        user_gift_id: int,
        *,
        to_user_id: int,
    ) -> tuple[UserStarGift, Message]:
        """Transfer a collectible gift; returns (gift, notice message in DM)."""
        import json as _json

        from app.services.chat_service import ChatService

        if owner_id == to_user_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot transfer to yourself"
            )
        recipient = (
            self.db.query(User)
            .filter(User.id == to_user_id, User.deleted_at.is_(None))
            .first()
        )
        if not recipient:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
        owned = (
            self.db.query(UserStarGift)
            .filter(UserStarGift.id == user_gift_id, UserStarGift.owner_id == owner_id)
            .with_for_update()
            .first()
        )
        if not owned:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Gift not found")
        if owned.status not in ("held", "kept"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Gift cannot be transferred"
            )
        if not bool(getattr(owned, "is_collectible", False)):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Only collectible gifts can be transferred",
            )
        if int(getattr(owned, "listed_stars", 0) or 0) > 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Take the gift off sale before transferring",
            )
        fee = 0
        total_supply = None
        if owned.gift_id:
            catalog = self.db.query(StarGift).filter(StarGift.id == owned.gift_id).first()
            if catalog is not None:
                fee = int(getattr(catalog, "transfer_stars", 0) or 0)
                total_supply = getattr(catalog, "total_supply", None)
        if fee <= 0:
            fee = max(25, int(owned.stars) // 10)
        import secrets

        # Unique key per transfer attempt: ownership moves after success,
        # so a retry from the old owner 404s; avoid reusable keys that
        # would skip the fee on A→B→A→B loops.
        self._spend_stars(
            owner_id,
            fee,
            tx_type="gift_transfer_fee",
            reference_type="user_gift",
            reference_id=owned.id,
            counterparty_user_id=to_user_id,
            idempotency_key=(
                f"gift_transfer_fee:{owned.id}:{owner_id}:{to_user_id}:"
                f"{secrets.token_hex(8)}"
            ),
            meta={"to_user_id": to_user_id, "serial": owned.serial},
        )
        # Retire actions on the original gift bubble.
        self._patch_gift_message_status(
            owned,
            status="transferred",
            extra={
                "is_collectible": True,
                "serial": owned.serial,
                "transferred_to_user_id": to_user_id,
            },
        )
        try:
            conv = ChatService(self.db).get_or_create_direct(owner_id, to_user_id)
        except ValueError as exc:
            code = str(exc)
            if code == "user_blocked":
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN, detail="User is blocked"
                ) from exc
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot open chat"
            ) from exc

        notice = Message(
            conversation_id=conv.id,
            sender_id=owner_id,
            type="gift",
            content="{}",
            media_url=None,
        )
        self.db.add(notice)
        self.db.flush()

        owned.transferred_from_user_id = owner_id
        owned.owner_id = to_user_id
        owned.status = "kept"
        owned.is_displayed = True
        owned.message_id = notice.id
        notice.content = _json.dumps(
            {
                "gift_id": owned.gift_id,
                "user_gift_id": owned.id,
                "slug": owned.slug,
                "title": owned.title,
                "emoji": owned.emoji,
                "stars": owned.stars,
                "message": None,
                "status": "kept",
                "is_collectible": True,
                "serial": owned.serial,
                "total_supply": total_supply,
                "transferred_from_user_id": owner_id,
            },
            ensure_ascii=False,
        )
        conv.updated_at = datetime.utcnow()
        self.db.flush()
        return owned, notice

    @staticmethod
    def resale_fee_stars(price: int) -> int:
        """Telegram-like marketplace commission: 5%, waived under 20 ★."""
        price = max(0, int(price or 0))
        if price < 20:
            return 0
        return max(1, price * 5 // 100)

    def _clear_gift_listing(self, gift: UserStarGift) -> None:
        gift.listed_stars = None
        gift.listed_at = None

    def list_marketplace_star_gifts(self, *, limit: int = 50) -> list[UserStarGift]:
        limit = max(1, min(int(limit or 50), 100))
        return (
            self.db.query(UserStarGift)
            .filter(
                UserStarGift.listed_stars.isnot(None),
                UserStarGift.listed_stars > 0,
                UserStarGift.status.in_(("held", "kept")),
                UserStarGift.is_collectible.is_(True),
            )
            .order_by(UserStarGift.listed_at.desc(), UserStarGift.id.desc())
            .limit(limit)
            .all()
        )

    def list_star_gift_for_sale(
        self, owner_id: int, user_gift_id: int, *, listed_stars: int
    ) -> UserStarGift:
        price = int(listed_stars)
        if price < 1 or price > 100000:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid listing price"
            )
        gift = (
            self.db.query(UserStarGift)
            .filter(UserStarGift.id == user_gift_id, UserStarGift.owner_id == owner_id)
            .with_for_update()
            .first()
        )
        if not gift:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Gift not found")
        if gift.status not in ("held", "kept"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Gift cannot be listed"
            )
        if not bool(getattr(gift, "is_collectible", False)):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Only collectible gifts can be listed",
            )
        gift.listed_stars = price
        gift.listed_at = datetime.utcnow()
        self.db.flush()
        return gift

    def unlist_star_gift(self, owner_id: int, user_gift_id: int) -> UserStarGift:
        gift = (
            self.db.query(UserStarGift)
            .filter(UserStarGift.id == user_gift_id, UserStarGift.owner_id == owner_id)
            .with_for_update()
            .first()
        )
        if not gift:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Gift not found")
        self._clear_gift_listing(gift)
        self.db.flush()
        return gift

    def set_user_star_gift_worn(
        self, owner_id: int, user_gift_id: int, *, worn: bool
    ) -> UserStarGift:
        gift = (
            self.db.query(UserStarGift)
            .filter(UserStarGift.id == user_gift_id, UserStarGift.owner_id == owner_id)
            .with_for_update()
            .first()
        )
        if not gift:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Gift not found")
        if gift.status not in ("held", "kept"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Gift cannot be worn"
            )
        if worn and not bool(getattr(gift, "is_collectible", False)):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Only collectible gifts can be worn",
            )
        if worn:
            (
                self.db.query(UserStarGift)
                .filter(
                    UserStarGift.owner_id == owner_id,
                    UserStarGift.id != gift.id,
                    UserStarGift.is_worn.is_(True),
                )
                .update({"is_worn": False}, synchronize_session=False)
            )
            gift.is_worn = True
            gift.is_displayed = True
        else:
            gift.is_worn = False
        self.db.flush()
        return gift

    def buy_listed_star_gift(
        self, buyer_id: int, user_gift_id: int
    ) -> tuple[UserStarGift, Message]:
        """Buy a listed collectible. Buyer pays listed price; seller gets price − fee."""
        import json as _json
        import secrets

        from app.services.chat_service import ChatService

        gift = (
            self.db.query(UserStarGift)
            .filter(UserStarGift.id == user_gift_id)
            .with_for_update()
            .first()
        )
        if not gift:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Gift not found")
        seller_id = int(gift.owner_id)
        if seller_id == buyer_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot buy your own gift"
            )
        price = int(getattr(gift, "listed_stars", 0) or 0)
        if price <= 0 or gift.status not in ("held", "kept"):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT, detail="Gift is not for sale"
            )
        if not bool(getattr(gift, "is_collectible", False)):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Only collectible gifts can be bought",
            )
        buyer = (
            self.db.query(User)
            .filter(User.id == buyer_id, User.deleted_at.is_(None))
            .first()
        )
        if not buyer:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
        fee = self.resale_fee_stars(price)
        seller_credit = price - fee
        self._spend_stars(
            buyer_id,
            price,
            tx_type="gift_resale",
            reference_type="user_gift",
            reference_id=gift.id,
            counterparty_user_id=seller_id,
            idempotency_key=f"gift_resale:{gift.id}:{buyer_id}:{secrets.token_hex(8)}",
            meta={"seller_id": seller_id, "serial": gift.serial, "fee": fee},
        )
        if seller_credit > 0:
            self.add_stars(
                seller_id,
                seller_credit,
                tx_type="gift_resale_received",
                idempotency_key=f"gift_resale_recv:{gift.id}:{seller_id}:{buyer_id}:{secrets.token_hex(8)}",
                meta={"buyer_id": buyer_id, "user_gift_id": gift.id, "fee": fee},
            )
            balance = self.creator_balance(seller_id)
            balance.available_stars = int(balance.available_stars or 0) + seller_credit
        total_supply = None
        if gift.gift_id:
            catalog = self.db.query(StarGift).filter(StarGift.id == gift.gift_id).first()
            if catalog is not None:
                total_supply = getattr(catalog, "total_supply", None)
        self._patch_gift_message_status(
            gift,
            status="sold",
            extra={
                "is_collectible": True,
                "serial": gift.serial,
                "sold_to_user_id": buyer_id,
                "listed_stars": price,
            },
        )
        try:
            conv = ChatService(self.db).get_or_create_direct(seller_id, buyer_id)
        except ValueError as exc:
            code = str(exc)
            if code == "user_blocked":
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN, detail="User is blocked"
                ) from exc
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot open chat"
            ) from exc

        notice = Message(
            conversation_id=conv.id,
            sender_id=seller_id,
            type="gift",
            content="{}",
            media_url=None,
        )
        self.db.add(notice)
        self.db.flush()

        gift.transferred_from_user_id = seller_id
        gift.owner_id = buyer_id
        gift.status = "kept"
        gift.is_displayed = True
        gift.is_worn = False
        gift.message_id = notice.id
        self._clear_gift_listing(gift)
        notice.content = _json.dumps(
            {
                "gift_id": gift.gift_id,
                "user_gift_id": gift.id,
                "slug": gift.slug,
                "title": gift.title,
                "emoji": gift.emoji,
                "stars": gift.stars,
                "message": None,
                "status": "kept",
                "is_collectible": True,
                "serial": gift.serial,
                "total_supply": total_supply,
                "transferred_from_user_id": seller_id,
                "purchased_stars": price,
            },
            ensure_ascii=False,
        )
        conv.updated_at = datetime.utcnow()
        self.db.flush()
        return gift, notice

    def cancel_star_invoice(self, actor_user_id: int, invoice_id: int) -> StarInvoice:
        invoice = (
            self.db.query(StarInvoice)
            .filter(StarInvoice.id == invoice_id)
            .with_for_update()
            .first()
        )
        if not invoice:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invoice not found")
        if invoice.creator_user_id != actor_user_id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not invoice owner")
        if invoice.status != "pending":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Invoice is not pending"
            )
        invoice.status = "cancelled"
        self.db.flush()
        return invoice

    def list_bot_star_invoices(
        self,
        actor_user_id: int,
        bot_id: int,
        *,
        status_filter: Optional[str] = None,
        limit: int = 50,
    ) -> list[StarInvoice]:
        bot = (
            self.db.query(User)
            .filter(User.id == bot_id, User.is_bot.is_(True), User.deleted_at.is_(None))
            .first()
        )
        if not bot:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bot not found")
        if int(getattr(bot, "created_by_user_id", 0) or 0) != actor_user_id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not bot owner")
        limit = max(1, min(int(limit or 50), 100))
        q = self.db.query(StarInvoice).filter(StarInvoice.bot_id == bot_id)
        if status_filter:
            q = q.filter(StarInvoice.status == status_filter.strip().lower())
        return (
            q.order_by(StarInvoice.created_at.desc(), StarInvoice.id.desc())
            .limit(limit)
            .all()
        )

    def refund_star_invoice(self, actor_user_id: int, invoice_id: int) -> StarInvoice:
        """Telegram-like refundStarPayment: claw back from creator, credit payer."""
        invoice = (
            self.db.query(StarInvoice)
            .filter(StarInvoice.id == invoice_id)
            .with_for_update()
            .first()
        )
        if not invoice:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invoice not found")
        if invoice.creator_user_id != actor_user_id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not invoice owner")
        if invoice.status == "refunded":
            return invoice
        if invoice.status != "paid":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Only paid invoices can be refunded"
            )
        if not invoice.payer_user_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Invoice has no payer"
            )
        amount = int(invoice.amount_stars)
        # Claw back from creator wallet (requires sufficient Stars balance).
        self._spend_stars(
            actor_user_id,
            amount,
            tx_type="invoice_refund_debit",
            reference_type="invoice",
            reference_id=invoice.id,
            counterparty_user_id=invoice.payer_user_id,
            idempotency_key=f"invoice_refund_debit:{invoice.id}",
            meta={"bot_id": invoice.bot_id, "payload": invoice.payload},
        )
        balance = self.creator_balance(actor_user_id)
        balance.available_stars = max(0, int(balance.available_stars or 0) - amount)
        self.add_stars(
            int(invoice.payer_user_id),
            amount,
            tx_type="invoice_refund",
            idempotency_key=f"invoice_refund:{invoice.id}",
            meta={
                "bot_id": invoice.bot_id,
                "invoice_id": invoice.id,
                "creator_user_id": actor_user_id,
            },
        )
        invoice.status = "refunded"
        self.db.flush()
        return invoice

    _REFUND_WINDOW = timedelta(hours=48)
    PREMIUM_STARS_PER_MONTH = 250

    def refund_paid_media(self, actor_user_id: int, message_id: int) -> int:
        """Author refunds all completed unlocks for a paid media message/album."""
        message = (
            self.db.query(Message)
            .filter(Message.id == message_id, Message.deleted_at.is_(None))
            .first()
        )
        if not message:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Message not found")
        if message.sender_id != actor_user_id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not media author")
        if not getattr(message, "is_paid", False):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Message is not paid")
        group_id = (getattr(message, "media_group_id", None) or "").strip()
        message_ids = [message.id]
        if group_id:
            message_ids = [
                int(row[0])
                for row in self.db.query(Message.id)
                .filter(
                    Message.conversation_id == message.conversation_id,
                    Message.media_group_id == group_id,
                    Message.deleted_at.is_(None),
                    Message.is_paid.is_(True),
                )
                .all()
            ] or [message.id]
        unlocks = (
            self.db.query(PaidMessageUnlock)
            .filter(
                PaidMessageUnlock.message_id.in_(message_ids),
                PaidMessageUnlock.status == "completed",
                PaidMessageUnlock.amount_stars > 0,
            )
            .with_for_update()
            .all()
        )
        if not unlocks:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Nothing to refund"
            )
        now = datetime.utcnow()
        refunded = 0
        for unlock in unlocks:
            created = unlock.created_at or now
            if now - created > self._REFUND_WINDOW:
                continue
            amount = int(unlock.amount_stars)
            if amount <= 0:
                unlock.status = "refunded"
                continue
            self._spend_stars(
                actor_user_id,
                amount,
                tx_type="paid_media_refund_debit",
                reference_type="message",
                reference_id=unlock.message_id,
                counterparty_user_id=unlock.user_id,
                idempotency_key=f"paid_media_refund_debit:{unlock.id}",
            )
            balance = self.creator_balance(actor_user_id)
            balance.available_stars = max(0, int(balance.available_stars or 0) - amount)
            self.add_stars(
                unlock.user_id,
                amount,
                tx_type="paid_media_refund",
                idempotency_key=f"paid_media_refund:{unlock.id}",
                meta={"message_id": unlock.message_id, "author_id": actor_user_id},
            )
            unlock.status = "refunded"
            refunded += 1
        if refunded <= 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Refund window expired",
            )
        self.db.flush()
        return refunded

    def refund_star_gift(self, actor_user_id: int, user_gift_id: int) -> UserStarGift:
        """Sender refunds an unconverted gift within 48 hours (Telegram-like)."""
        gift = (
            self.db.query(UserStarGift)
            .filter(UserStarGift.id == user_gift_id)
            .with_for_update()
            .first()
        )
        if not gift:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Gift not found")
        if gift.sender_id != actor_user_id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not gift sender")
        if gift.status == "refunded":
            return gift
        if gift.status not in ("held", "kept"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Gift cannot be refunded"
            )
        if bool(getattr(gift, "is_collectible", False)):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Collectible gifts cannot be refunded",
            )
        created = gift.created_at or datetime.utcnow()
        if datetime.utcnow() - created > self._REFUND_WINDOW:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Refund window expired"
            )
        amount = int(gift.stars)
        self.add_stars(
            actor_user_id,
            amount,
            tx_type="gift_refund",
            idempotency_key=f"gift_refund:{gift.id}",
            meta={"user_gift_id": gift.id, "owner_id": gift.owner_id},
        )
        gift.status = "refunded"
        gift.is_displayed = False
        self._patch_gift_message_status(gift, status="refunded")
        self.db.flush()
        return gift

    def _grant_premium_months(self, user_id: int, months: int) -> None:
        user = self.db.query(User).filter(User.id == user_id, User.deleted_at.is_(None)).first()
        if not user or months <= 0:
            return
        from app.services.flex_subscription_service import FlexSubscriptionService

        FlexSubscriptionService(self.db).grant_gift_access(
            user_id,
            level=10,
            extra_days=30 * int(months),
        )

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

    def _patch_gift_message_status(
        self,
        gift: UserStarGift,
        *,
        status: str,
        extra: Optional[dict] = None,
    ) -> None:
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
        if extra:
            payload.update(extra)
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

    def _channel_manage_access(self, user_id: int, channel_id: int) -> Channel:
        from app.models.community_member import ChannelMember
        from app.services.channel_membership_service import (
            MEMBER_STATUS_ACTIVE,
            is_channel_owner,
        )

        channel = self.db.query(Channel).filter(Channel.id == channel_id).first()
        if not channel:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Channel not found")
        user = self.db.query(User).filter(User.id == user_id, User.deleted_at.is_(None)).first()
        if not user:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
        if is_channel_owner(channel, user):
            return channel
        member = (
            self.db.query(ChannelMember)
            .filter(
                ChannelMember.channel_id == channel_id,
                ChannelMember.user_id == user_id,
                ChannelMember.status == MEMBER_STATUS_ACTIVE,
                ChannelMember.role.in_(("owner", "admin")),
            )
            .first()
        )
        if member is None:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not channel admin")
        return channel

    def create_star_giveaway(
        self,
        user_id: int,
        channel_id: int,
        *,
        prize_stars: int = 0,
        winners_count: int,
        duration_hours: int,
        title: Optional[str] = None,
        prize_type: str = "stars",
        premium_months: int = 0,
    ) -> StarGiveaway:
        kind = (prize_type or "stars").strip().lower()
        if kind not in ("stars", "premium"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid prize type"
            )
        months = int(premium_months or 0)
        if kind == "premium":
            if months not in (1, 3, 6, 12):
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Premium months must be 1, 3, 6 or 12",
                )
            prize_stars = self.PREMIUM_STARS_PER_MONTH * months
        elif prize_stars < 1 or prize_stars > 100_000:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Prize must be between 1 and 100000 stars",
            )
        if winners_count < 1 or winners_count > 100:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Winners count must be between 1 and 100",
            )
        if duration_hours < 1 or duration_hours > 24 * 30:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Duration must be between 1 hour and 30 days",
            )
        from app.services.emoji_pack_service import EmojiPackService

        EmojiPackService(self.db).require_send_tokens_http(user_id, title)
        self._channel_manage_access(user_id, channel_id)
        active = (
            self.db.query(StarGiveaway.id)
            .filter(
                StarGiveaway.channel_id == channel_id,
                StarGiveaway.status == "active",
            )
            .first()
        )
        if active is not None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Channel already has an active giveaway",
            )
        escrow = int(prize_stars) * int(winners_count)
        giveaway = StarGiveaway(
            channel_id=channel_id,
            creator_user_id=user_id,
            prize_stars=int(prize_stars),
            winners_count=int(winners_count),
            total_escrow_stars=escrow,
            status="active",
            ends_at=datetime.utcnow() + timedelta(hours=int(duration_hours)),
            require_membership=True,
            participants_count=0,
            title=(title or "").strip()[:160] or None,
            prize_type=kind,
            premium_months=months if kind == "premium" else 0,
        )
        self.db.add(giveaway)
        self.db.flush()
        self._spend_stars(
            user_id,
            escrow,
            tx_type="giveaway_escrow",
            reference_type="giveaway",
            reference_id=giveaway.id,
            counterparty_user_id=None,
            idempotency_key=f"giveaway_escrow:{giveaway.id}",
            meta={"channel_id": channel_id, "winners_count": winners_count},
        )
        self.db.flush()
        return giveaway

    def list_channel_giveaways(
        self, channel_id: int, *, active_only: bool = False, limit: int = 20
    ) -> list[StarGiveaway]:
        limit = max(1, min(int(limit or 20), 50))
        q = self.db.query(StarGiveaway).filter(StarGiveaway.channel_id == channel_id)
        if active_only:
            q = q.filter(StarGiveaway.status == "active")
        return q.order_by(StarGiveaway.created_at.desc(), StarGiveaway.id.desc()).limit(limit).all()

    def get_giveaway(self, giveaway_id: int) -> StarGiveaway:
        row = self.db.query(StarGiveaway).filter(StarGiveaway.id == giveaway_id).first()
        if not row:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Giveaway not found")
        return row

    def join_star_giveaway(self, user_id: int, giveaway_id: int) -> StarGiveawayParticipant:
        from app.models.community_member import ChannelMember
        from app.services.channel_membership_service import (
            MEMBER_STATUS_ACTIVE,
            is_channel_owner,
        )

        giveaway = (
            self.db.query(StarGiveaway)
            .filter(StarGiveaway.id == giveaway_id)
            .with_for_update()
            .first()
        )
        if not giveaway:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Giveaway not found")
        if giveaway.status != "active":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Giveaway is not active"
            )
        now = datetime.utcnow()
        if giveaway.ends_at <= now:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Giveaway already ended"
            )
        if giveaway.creator_user_id == user_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Creator cannot join own giveaway",
            )
        existing = (
            self.db.query(StarGiveawayParticipant)
            .filter(
                StarGiveawayParticipant.giveaway_id == giveaway_id,
                StarGiveawayParticipant.user_id == user_id,
            )
            .first()
        )
        if existing is not None:
            return existing
        channel = self.db.query(Channel).filter(Channel.id == giveaway.channel_id).first()
        user = self.db.query(User).filter(User.id == user_id, User.deleted_at.is_(None)).first()
        if not channel or not user:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")
        if giveaway.require_membership and not is_channel_owner(channel, user):
            member = (
                self.db.query(ChannelMember)
                .filter(
                    ChannelMember.channel_id == giveaway.channel_id,
                    ChannelMember.user_id == user_id,
                    ChannelMember.status == MEMBER_STATUS_ACTIVE,
                )
                .first()
            )
            if member is None:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Join the channel to enter the giveaway",
                )
        row = StarGiveawayParticipant(giveaway_id=giveaway_id, user_id=user_id)
        self.db.add(row)
        giveaway.participants_count = int(giveaway.participants_count or 0) + 1
        self.db.flush()
        return row

    def cancel_star_giveaway(self, user_id: int, giveaway_id: int) -> StarGiveaway:
        giveaway = (
            self.db.query(StarGiveaway)
            .filter(StarGiveaway.id == giveaway_id)
            .with_for_update()
            .first()
        )
        if not giveaway:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Giveaway not found")
        self._channel_manage_access(user_id, giveaway.channel_id)
        if giveaway.status != "active":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Giveaway is not active"
            )
        remaining = int(giveaway.total_escrow_stars or 0)
        if remaining > 0:
            self.add_stars(
                giveaway.creator_user_id,
                remaining,
                tx_type="giveaway_refund",
                idempotency_key=f"giveaway_refund:{giveaway.id}",
                meta={"giveaway_id": giveaway.id},
            )
        giveaway.status = "cancelled"
        giveaway.completed_at = datetime.utcnow()
        self.db.flush()
        return giveaway

    def finalize_star_giveaway(self, giveaway_id: int) -> StarGiveaway:
        import random

        giveaway = (
            self.db.query(StarGiveaway)
            .filter(StarGiveaway.id == giveaway_id)
            .with_for_update()
            .first()
        )
        if not giveaway:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Giveaway not found")
        if giveaway.status != "active":
            return giveaway
        participants = (
            self.db.query(StarGiveawayParticipant)
            .filter(StarGiveawayParticipant.giveaway_id == giveaway_id)
            .all()
        )
        winners_n = min(int(giveaway.winners_count), len(participants))
        winners = random.sample(participants, winners_n) if winners_n else []
        prize = int(giveaway.prize_stars)
        prize_kind = getattr(giveaway, "prize_type", "stars") or "stars"
        months = int(getattr(giveaway, "premium_months", 0) or 0)
        paid_out = 0
        for winner in winners:
            winner.is_winner = True
            if prize_kind == "premium" and months > 0:
                self._grant_premium_months(winner.user_id, months)
            else:
                self.add_stars(
                    winner.user_id,
                    prize,
                    tx_type="giveaway_prize",
                    idempotency_key=f"giveaway_prize:{giveaway.id}:{winner.user_id}",
                    meta={"giveaway_id": giveaway.id, "channel_id": giveaway.channel_id},
                )
            paid_out += prize
        refund = int(giveaway.total_escrow_stars or 0) - paid_out
        if refund > 0:
            self.add_stars(
                giveaway.creator_user_id,
                refund,
                tx_type="giveaway_refund",
                idempotency_key=f"giveaway_refund:{giveaway.id}",
                meta={"giveaway_id": giveaway.id, "unused_prizes": refund // max(prize, 1)},
            )
        giveaway.status = "completed"
        giveaway.completed_at = datetime.utcnow()
        self.db.flush()
        return giveaway

    def list_giveaway_winners(
        self, giveaway_id: int
    ) -> tuple[StarGiveaway, list[tuple[StarGiveawayParticipant, User]]]:
        """Return (giveaway, [(participant, user), ...]) for winners."""
        giveaway = self.get_giveaway(giveaway_id)
        if giveaway.status != "completed":
            return giveaway, []
        rows = (
            self.db.query(StarGiveawayParticipant, User)
            .join(User, User.id == StarGiveawayParticipant.user_id)
            .filter(
                StarGiveawayParticipant.giveaway_id == giveaway_id,
                StarGiveawayParticipant.is_winner.is_(True),
            )
            .order_by(StarGiveawayParticipant.id.asc())
            .all()
        )
        return giveaway, rows

    def suggest_channel_post(
        self,
        user_id: int,
        channel_id: int,
        *,
        text: str,
        amount_stars: int,
        media_url: Optional[str] = None,
    ) -> ChannelSuggestedPost:
        clean = (text or "").strip()
        if not clean:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Text required")
        from app.services.emoji_pack_service import EmojiPackService

        EmojiPackService(self.db).require_send_tokens_http(user_id, clean)
        if amount_stars < 10 or amount_stars > 100_000:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Amount must be between 10 and 100000 stars",
            )
        channel = self.db.query(Channel).filter(Channel.id == channel_id).first()
        if not channel:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Channel not found")
        if int(getattr(channel, "admin_user_id", 0) or 0) == user_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Channel owner cannot suggest to self",
            )
        row = ChannelSuggestedPost(
            channel_id=channel_id,
            author_id=user_id,
            text=clean[:2000],
            media_url=(media_url or "").strip()[:1024] or None,
            amount_stars=int(amount_stars),
            status="pending",
        )
        self.db.add(row)
        self.db.flush()
        self._spend_stars(
            user_id,
            int(amount_stars),
            tx_type="suggested_post",
            reference_type="suggested_post",
            reference_id=row.id,
            counterparty_user_id=int(channel.admin_user_id or 0) or None,
            idempotency_key=f"suggested_post:{row.id}",
            meta={"channel_id": channel_id},
        )
        self.db.flush()
        return row

    def list_channel_suggested_posts(
        self,
        user_id: int,
        channel_id: int,
        *,
        status_filter: Optional[str] = None,
        limit: int = 40,
    ) -> list[ChannelSuggestedPost]:
        from app.models.community_member import ChannelMember
        from app.services.channel_membership_service import (
            MEMBER_STATUS_ACTIVE,
            is_channel_owner,
        )

        channel = self.db.query(Channel).filter(Channel.id == channel_id).first()
        if not channel:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Channel not found")
        user = self.db.query(User).filter(User.id == user_id, User.deleted_at.is_(None)).first()
        if not user:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
        is_manager = is_channel_owner(channel, user)
        if not is_manager:
            member = (
                self.db.query(ChannelMember)
                .filter(
                    ChannelMember.channel_id == channel_id,
                    ChannelMember.user_id == user_id,
                    ChannelMember.status == MEMBER_STATUS_ACTIVE,
                    ChannelMember.role.in_(("owner", "admin")),
                )
                .first()
            )
            is_manager = member is not None
        limit = max(1, min(int(limit or 40), 80))
        q = self.db.query(ChannelSuggestedPost).filter(
            ChannelSuggestedPost.channel_id == channel_id
        )
        if not is_manager:
            q = q.filter(ChannelSuggestedPost.author_id == user_id)
        if status_filter:
            q = q.filter(ChannelSuggestedPost.status == status_filter.strip().lower())
        return (
            q.order_by(ChannelSuggestedPost.created_at.desc(), ChannelSuggestedPost.id.desc())
            .limit(limit)
            .all()
        )

    def review_suggested_post(
        self, user_id: int, suggestion_id: int, *, approve: bool
    ) -> ChannelSuggestedPost:
        row = (
            self.db.query(ChannelSuggestedPost)
            .filter(ChannelSuggestedPost.id == suggestion_id)
            .with_for_update()
            .first()
        )
        if not row:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Suggestion not found")
        channel = self._channel_manage_access(user_id, row.channel_id)
        if row.status != "pending":
            return row
        if approve:
            body = None
            if row.media_url:
                body = {"media": [{"type": "image", "url": row.media_url}]}
            import json as _json
            from sqlalchemy import text as sa_text

            inserted = self.db.execute(
                sa_text(
                    "INSERT INTO posts (user_id, channel_id, type, description, body, "
                    "status, visibility, published_at) VALUES (:user_id, :channel_id, "
                    ":type, :description, :body, :status, :visibility, :published_at) "
                    "RETURNING id"
                ),
                {
                    "user_id": user_id,
                    "channel_id": row.channel_id,
                    "type": "photo" if row.media_url else "text",
                    "description": row.text,
                    "body": _json.dumps(body) if body else None,
                    "status": "published",
                    "visibility": "public",
                    "published_at": datetime.utcnow(),
                },
            )
            post_id = int(inserted.scalar_one())
            channel.posts_count = int(channel.posts_count or 0) + 1
            self.db.flush()
            row.post_id = post_id
            row.status = "accepted"
            self._credit_creator(
                user_id,
                int(row.amount_stars),
                tx_type="suggested_post_received",
                reference_type="suggested_post",
                reference_id=row.id,
                counterparty_user_id=row.author_id,
                meta={"channel_id": row.channel_id, "post_id": post_id},
            )
        else:
            self.add_stars(
                row.author_id,
                int(row.amount_stars),
                tx_type="suggested_post_refund",
                idempotency_key=f"suggested_post_refund:{row.id}",
                meta={"channel_id": row.channel_id},
            )
            row.status = "rejected"
        self.db.flush()
        return row

    def create_star_invoice(
        self,
        creator_user_id: int,
        bot_id: int,
        *,
        title: str,
        amount_stars: int,
        description: Optional[str] = None,
        payload: Optional[str] = None,
        expires_in_hours: int = 24,
    ) -> StarInvoice:
        bot = (
            self.db.query(User)
            .filter(User.id == bot_id, User.is_bot.is_(True), User.deleted_at.is_(None))
            .first()
        )
        if not bot:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bot not found")
        if int(getattr(bot, "created_by_user_id", 0) or 0) != creator_user_id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not bot owner")
        clean_title = (title or "").strip()
        if not clean_title:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Title required")
        from app.services.emoji_pack_service import EmojiPackService

        EmojiPackService(self.db).require_send_tokens_http(
            creator_user_id,
            clean_title,
            description,
        )
        if amount_stars < 1 or amount_stars > 100_000:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Amount must be between 1 and 100000",
            )
        if expires_in_hours < 1 or expires_in_hours > 24 * 30:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Expiry must be between 1 hour and 30 days",
            )
        invoice = StarInvoice(
            bot_id=bot_id,
            creator_user_id=creator_user_id,
            title=clean_title[:160],
            description=((description or "").strip()[:512] or None),
            amount_stars=int(amount_stars),
            payload=((payload or "").strip()[:256] or None),
            status="pending",
            expires_at=datetime.utcnow() + timedelta(hours=int(expires_in_hours)),
        )
        self.db.add(invoice)
        self.db.flush()
        return invoice

    def get_star_invoice(self, invoice_id: int) -> StarInvoice:
        row = self.db.query(StarInvoice).filter(StarInvoice.id == invoice_id).first()
        if not row:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invoice not found")
        return row

    def pay_star_invoice(self, payer_user_id: int, invoice_id: int) -> StarInvoice:
        invoice = (
            self.db.query(StarInvoice)
            .filter(StarInvoice.id == invoice_id)
            .with_for_update()
            .first()
        )
        if not invoice:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invoice not found")
        if invoice.status == "paid":
            if invoice.payer_user_id == payer_user_id:
                return invoice
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Invoice already paid"
            )
        if invoice.status != "pending":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Invoice is not payable"
            )
        now = datetime.utcnow()
        if invoice.expires_at and invoice.expires_at <= now:
            invoice.status = "expired"
            self.db.flush()
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Invoice expired"
            )
        if payer_user_id in (invoice.bot_id, invoice.creator_user_id):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot pay own invoice"
            )
        self._spend_stars(
            payer_user_id,
            int(invoice.amount_stars),
            tx_type="invoice_payment",
            reference_type="invoice",
            reference_id=invoice.id,
            counterparty_user_id=invoice.creator_user_id,
            idempotency_key=f"invoice_pay:{invoice.id}:{payer_user_id}",
            meta={"bot_id": invoice.bot_id, "payload": invoice.payload},
        )
        self._credit_creator(
            invoice.creator_user_id,
            int(invoice.amount_stars),
            tx_type="invoice_received",
            reference_type="invoice",
            reference_id=invoice.id,
            counterparty_user_id=payer_user_id,
            meta={"bot_id": invoice.bot_id, "payload": invoice.payload},
        )
        invoice.status = "paid"
        invoice.payer_user_id = payer_user_id
        invoice.paid_at = now
        self.db.flush()
        return invoice


def finalize_due_star_giveaways(db: Session) -> int:
    """Complete giveaways whose ends_at has passed."""
    now = datetime.utcnow()
    due = (
        db.query(StarGiveaway)
        .filter(
            StarGiveaway.status == "active",
            StarGiveaway.ends_at <= now,
        )
        .limit(50)
        .all()
    )
    if not due:
        return 0
    service = PaidFeaturesService(db)
    changed = 0
    for giveaway in due:
        service.finalize_star_giveaway(giveaway.id)
        changed += 1
    return changed


def expire_due_star_invoices(db: Session) -> int:
    now = datetime.utcnow()
    rows = (
        db.query(StarInvoice)
        .filter(
            StarInvoice.status == "pending",
            StarInvoice.expires_at.isnot(None),
            StarInvoice.expires_at <= now,
        )
        .limit(100)
        .all()
    )
    for row in rows:
        row.status = "expired"
    return len(rows)


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


def expire_due_group_subscriptions(db: Session) -> int:
    now = datetime.utcnow()
    due = (
        db.query(PaidGroupSubscription)
        .filter(
            PaidGroupSubscription.status == "active",
            PaidGroupSubscription.expires_at.isnot(None),
            PaidGroupSubscription.expires_at <= now,
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
                service.subscribe_group(
                    sub.user_id,
                    sub.conversation_id,
                    months=1,
                    auto_renew=True,
                )
                renewed = True
                changed += 1
            except Exception:
                renewed = False
        if renewed:
            continue
        sub.status = "expired"
        conv = db.query(Conversation).filter(Conversation.id == sub.conversation_id).first()
        if conv and conv.created_by_user_id != sub.user_id:
            member = (
                db.query(ConversationMember)
                .filter(
                    ConversationMember.conversation_id == sub.conversation_id,
                    ConversationMember.user_id == sub.user_id,
                )
                .first()
            )
            if member is not None and not member.is_admin:
                db.delete(member)
        changed += 1
    return changed

