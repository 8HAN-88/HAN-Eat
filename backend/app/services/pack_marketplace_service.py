"""Stars marketplace for sticker and custom-emoji packs."""

from __future__ import annotations

import secrets
from datetime import datetime, timezone
from typing import Literal, Optional

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.models.emoji_pack import CustomEmoji, EmojiPack, EmojiPackInstall, EmojiPackPurchase
from app.models.sticker import Sticker, StickerPack, StickerPackInstall, StickerPackPurchase
from app.models.user import User
from app.services.paid_features_service import PaidFeaturesService
from app.services.subscription_service import SubscriptionService

PackKind = Literal["sticker", "emoji"]
MAX_PRICE = 25000


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def marketplace_fee_stars(price: int) -> int:
    return PaidFeaturesService.resale_fee_stars(price)


def owner_labels(db: Session, user_ids) -> dict[int, str]:
    ids = {int(uid) for uid in user_ids if int(uid or 0) > 0}
    if not ids:
        return {}
    rows = (
        db.query(User.id, User.name, User.username)
        .filter(User.id.in_(ids))
        .all()
    )
    out: dict[int, str] = {}
    for uid, name, username in rows:
        label = (name or "").strip() or (username or "").strip()
        out[int(uid)] = label or f"id{uid}"
    return out


class PackMarketplaceService:
    def __init__(self, db: Session):
        self.db = db
        self.billing = SubscriptionService(db)
        self.stars = PaidFeaturesService(db)

    def _require(self, user_id: int, slug: str, message: str) -> None:
        self.billing.require_feature(user_id, slug, message)

    def list_sticker_pack(
        self, user_id: int, pack_id: int, price_stars: int
    ) -> StickerPack:
        pack = self.db.query(StickerPack).filter(StickerPack.id == pack_id).first()
        if not pack:
            raise ValueError("pack_not_found")
        if int(pack.owner_user_id) != int(user_id):
            raise ValueError("forbidden")
        price = max(0, int(price_stars or 0))
        if price > MAX_PRICE:
            raise ValueError("invalid_price")
        if price > 0:
            self._require(
                user_id,
                "sticker_pack_sell",
                "Продажа стикерпаков доступна с уровня 71",
            )
            has_items = (
                self.db.query(Sticker.id).filter(Sticker.pack_id == pack.id).first()
            )
            if has_items is None:
                raise ValueError("empty_pack")
            pack.price_stars = price
            pack.listed_at = _now()
            pack.is_public = True
        else:
            pack.price_stars = 0
            pack.listed_at = None
        pack.updated_at = _now()
        self.db.flush()
        return pack

    def list_emoji_pack(self, user_id: int, pack_id: int, price_stars: int) -> EmojiPack:
        pack = self.db.query(EmojiPack).filter(EmojiPack.id == pack_id).first()
        if not pack:
            raise ValueError("pack_not_found")
        if int(pack.owner_user_id) != int(user_id):
            raise ValueError("forbidden")
        price = max(0, int(price_stars or 0))
        if price > MAX_PRICE:
            raise ValueError("invalid_price")
        if price > 0:
            self._require(
                user_id,
                "emoji_pack_publish",
                "Продажа эмодзи-паков доступна с уровня 70",
            )
            has_items = (
                self.db.query(CustomEmoji.id).filter(CustomEmoji.pack_id == pack.id).first()
            )
            if has_items is None:
                raise ValueError("empty_pack")
            pack.price_stars = price
            pack.listed_at = _now()
            pack.is_public = True
        else:
            pack.price_stars = 0
            pack.listed_at = None
        pack.updated_at = _now()
        self.db.flush()
        return pack

    def has_sticker_access(self, user_id: int, pack: StickerPack) -> bool:
        if int(pack.owner_user_id) == int(user_id):
            return True
        if int(getattr(pack, "price_stars", 0) or 0) <= 0:
            return True
        bought = (
            self.db.query(StickerPackPurchase.id)
            .filter(
                StickerPackPurchase.user_id == user_id,
                StickerPackPurchase.pack_id == pack.id,
            )
            .first()
        )
        return bought is not None

    def has_emoji_access(self, user_id: int, pack: EmojiPack) -> bool:
        if int(pack.owner_user_id) == int(user_id):
            return True
        if int(getattr(pack, "price_stars", 0) or 0) <= 0:
            installed = (
                self.db.query(EmojiPackInstall.id)
                .filter(
                    EmojiPackInstall.user_id == user_id,
                    EmojiPackInstall.pack_id == pack.id,
                )
                .first()
            )
            return installed is not None
        bought = (
            self.db.query(EmojiPackPurchase.id)
            .filter(
                EmojiPackPurchase.user_id == user_id,
                EmojiPackPurchase.pack_id == pack.id,
            )
            .first()
        )
        return bought is not None

    def buy_sticker_pack(self, buyer_id: int, pack_id: int) -> dict:
        pack = self.db.query(StickerPack).filter(StickerPack.id == pack_id).first()
        if not pack or not pack.is_public:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "pack_not_found")
        return self._buy(
            kind="sticker",
            buyer_id=buyer_id,
            pack_id=pack.id,
            seller_id=int(pack.owner_user_id),
            price=int(getattr(pack, "price_stars", 0) or 0),
        )

    def buy_emoji_pack(self, buyer_id: int, pack_id: int) -> dict:
        pack = self.db.query(EmojiPack).filter(EmojiPack.id == pack_id).first()
        if not pack or not pack.is_public:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "pack_not_found")
        return self._buy(
            kind="emoji",
            buyer_id=buyer_id,
            pack_id=pack.id,
            seller_id=int(pack.owner_user_id),
            price=int(getattr(pack, "price_stars", 0) or 0),
        )

    def _buy(
        self,
        *,
        kind: PackKind,
        buyer_id: int,
        pack_id: int,
        seller_id: int,
        price: int,
    ) -> dict:
        if seller_id == buyer_id:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "own_pack")
        if price <= 0:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "not_for_sale")
        buyer = (
            self.db.query(User)
            .filter(User.id == buyer_id, User.deleted_at.is_(None))
            .first()
        )
        if not buyer:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
        purchase_cls = StickerPackPurchase if kind == "sticker" else EmojiPackPurchase
        existing = (
            self.db.query(purchase_cls)
            .filter(purchase_cls.user_id == buyer_id, purchase_cls.pack_id == pack_id)
            .first()
        )
        if existing:
            self._install_after_purchase(kind, buyer_id, pack_id)
            return {
                "ok": True,
                "already_owned": True,
                "price_stars": existing.amount_stars,
                "fee_stars": existing.fee_stars,
            }
        fee = marketplace_fee_stars(price)
        seller_credit = price - fee
        token = secrets.token_hex(8)
        self.stars._spend_stars(
            buyer_id,
            price,
            tx_type="pack_purchase",
            reference_type=f"{kind}_pack",
            reference_id=pack_id,
            counterparty_user_id=seller_id,
            idempotency_key=f"pack_buy:{kind}:{pack_id}:{buyer_id}:{token}",
            meta={"seller_id": seller_id, "fee": fee, "kind": kind},
        )
        if seller_credit > 0:
            self.stars.add_stars(
                seller_id,
                seller_credit,
                tx_type="pack_sale",
                idempotency_key=f"pack_sale:{kind}:{pack_id}:{seller_id}:{buyer_id}:{token}",
                meta={"buyer_id": buyer_id, "fee": fee, "kind": kind},
            )
            balance = self.stars.creator_balance(seller_id)
            balance.available_stars = int(balance.available_stars or 0) + seller_credit
        row = purchase_cls(
            user_id=buyer_id,
            pack_id=pack_id,
            seller_user_id=seller_id,
            amount_stars=price,
            fee_stars=fee,
        )
        self.db.add(row)
        self._install_after_purchase(kind, buyer_id, pack_id)
        self.db.flush()
        return {
            "ok": True,
            "already_owned": False,
            "price_stars": price,
            "fee_stars": fee,
            "seller_credit": seller_credit,
        }

    def _install_after_purchase(self, kind: PackKind, user_id: int, pack_id: int) -> None:
        if kind == "sticker":
            exists = (
                self.db.query(StickerPackInstall.id)
                .filter(
                    StickerPackInstall.user_id == user_id,
                    StickerPackInstall.pack_id == pack_id,
                )
                .first()
            )
            if exists is None:
                self.db.add(StickerPackInstall(user_id=user_id, pack_id=pack_id))
            return
        exists = (
            self.db.query(EmojiPackInstall.id)
            .filter(
                EmojiPackInstall.user_id == user_id,
                EmojiPackInstall.pack_id == pack_id,
            )
            .first()
        )
        if exists is None:
            self.db.add(EmojiPackInstall(user_id=user_id, pack_id=pack_id))
