import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base
from app.models.emoji_pack import CustomEmoji, EmojiPack, EmojiPackInstall, EmojiPackPurchase
from app.models.flex_subscription import (
    SubscriptionFeature,
    SubscriptionFeatureBlock,
    UserFlexGift,
    UserFlexSlot,
    UserFlexSubscription,
)
from app.models.paid_features import CreatorBalance, StarTransaction
from app.models.sticker import Sticker, StickerPack, StickerPackInstall, StickerPackPurchase
from app.models.subscription import Subscription
from app.models.user import User
from app.services.emoji_pack_service import EmojiPackService
from app.services.flex_subscription_service import FlexSubscriptionService
from app.services.pack_marketplace_service import PackMarketplaceService, marketplace_fee_stars
from app.services.paid_features_service import PaidFeaturesService
from app.services.sticker_service import StickerService
from app.services.subscription_service import SubscriptionService


@pytest.fixture()
def db_session():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(
        bind=engine,
        tables=[
            User.__table__,
            Subscription.__table__,
            SubscriptionFeatureBlock.__table__,
            SubscriptionFeature.__table__,
            UserFlexSubscription.__table__,
            UserFlexSlot.__table__,
            UserFlexGift.__table__,
            StarTransaction.__table__,
            CreatorBalance.__table__,
            StickerPack.__table__,
            Sticker.__table__,
            StickerPackInstall.__table__,
            StickerPackPurchase.__table__,
            EmojiPack.__table__,
            CustomEmoji.__table__,
            EmojiPackInstall.__table__,
            EmojiPackPurchase.__table__,
        ],
    )
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def _user(db, user_id: int) -> User:
    u = User(id=user_id, email=f"u{user_id}@t.test", password_hash="h", name=f"U{user_id}")
    db.add(u)
    db.commit()
    return u


def _activate(db, user_id: int, level: int) -> None:
    flex = FlexSubscriptionService(db)
    flex.ensure_catalog()
    flex.activate(user_id, level)
    db.commit()


def test_level_68_does_not_unlock_pack_store(db_session):
    _user(db_session, 1)
    _activate(db_session, 1, 68)
    billing = SubscriptionService(db_session)
    assert billing.has_feature(1, "profile_website") is True
    assert billing.has_feature(1, "custom_emoji") is False
    assert billing.has_feature(1, "emoji_pack_publish") is False
    assert billing.has_feature(1, "sticker_pack_sell") is False
    assert billing.has_feature(1, "custom_emoji_reactions") is False


def test_sticker_sale_and_commission(db_session):
    seller = _user(db_session, 1)
    buyer = _user(db_session, 2)
    _activate(db_session, 1, 70)
    stickers = StickerService(db_session)
    pack = stickers.create_pack(seller.id, "Котики", True)
    stickers.add_sticker(
        user_id=seller.id,
        pack_id=pack.id,
        media_url="https://cdn.test/a.webp",
    )
    db_session.commit()
    market = PackMarketplaceService(db_session)
    with pytest.raises(HTTPException) as err:
        market.list_sticker_pack(seller.id, pack.id, 100)
    assert err.value.status_code == 403
    _activate(db_session, 1, 71)
    market.list_sticker_pack(seller.id, pack.id, 100)
    db_session.commit()
    with pytest.raises(ValueError, match="pack_purchase_required"):
        stickers.install_pack(buyer.id, pack.id)
    PaidFeaturesService(db_session).add_stars(buyer.id, 200, tx_type="admin_adjust")
    db_session.commit()
    result = market.buy_sticker_pack(buyer.id, pack.id)
    db_session.commit()
    assert result["price_stars"] == 100
    assert result["fee_stars"] == marketplace_fee_stars(100)
    assert result["seller_credit"] == 100 - result["fee_stars"]
    stickers.install_pack(buyer.id, pack.id)
    stars = PaidFeaturesService(db_session)
    assert stars.star_balance(buyer.id) == 100
    assert stars.star_balance(seller.id) == result["seller_credit"]


def test_emoji_publish_buy_and_send_gate(db_session):
    seller = _user(db_session, 1)
    buyer = _user(db_session, 2)
    _activate(db_session, 1, 69)
    emoji = EmojiPackService(db_session)
    with pytest.raises(HTTPException):
        emoji.create_pack(seller.id, "Еда")
    _activate(db_session, 1, 70)
    pack = emoji.create_pack(seller.id, "Еда")
    item = emoji.add_emoji(
        user_id=seller.id,
        pack_id=pack.id,
        media_url="https://cdn.test/e.webp",
        shortcode="pizza",
    )
    PackMarketplaceService(db_session).list_emoji_pack(seller.id, pack.id, 40)
    db_session.commit()
    PaidFeaturesService(db_session).add_stars(buyer.id, 40, tx_type="admin_adjust")
    db_session.commit()
    PackMarketplaceService(db_session).buy_emoji_pack(buyer.id, pack.id)
    db_session.commit()
    token = f"[[e:{item.id}]]"
    with pytest.raises(ValueError, match="custom_emoji_required"):
        emoji.require_send_tokens(buyer.id, token)
    _activate(db_session, 2, 69)
    emoji.require_send_tokens(buyer.id, token)
    with pytest.raises(ValueError, match="custom_emoji_reaction_required"):
        emoji.require_reaction(buyer.id, f"ce:{item.id}")
    _activate(db_session, 2, 72)
    assert emoji.require_reaction(buyer.id, f"ce:{item.id}") == f"ce:{item.id}"
    assert emoji.require_status(buyer.id, f"[[e:{item.id}]]") == f"ce:{item.id}"


def test_custom_emoji_status_needs_access(db_session):
    seller = _user(db_session, 1)
    stranger = _user(db_session, 3)
    _activate(db_session, 1, 70)
    _activate(db_session, 3, 69)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(seller.id, "Статус")
    item = emoji.add_emoji(
        user_id=seller.id,
        pack_id=pack.id,
        media_url="https://cdn.test/s.webp",
    )
    PackMarketplaceService(db_session).list_emoji_pack(seller.id, pack.id, 25)
    db_session.commit()
    with pytest.raises(ValueError, match="custom_emoji_denied"):
        emoji.require_status(stranger.id, f"ce:{item.id}")
    assert emoji.require_status(seller.id, f"ce:{item.id}") == f"ce:{item.id}"
