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
from app.models.conversation import (
    Conversation,
    ConversationMember,
    Message,
    MessageEditHistory,
    ScheduledMessage,
)
from app.models.sticker import (
    Sticker,
    StickerFavorite,
    StickerPack,
    StickerPackInstall,
    StickerPackPin,
    StickerPackPurchase,
)
from app.models.subscription import Subscription
from app.models.user import User
from app.services.emoji_pack_service import (
    EmojiPackService,
    preview_text_with_custom_emoji,
)
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
            StickerPackPin.__table__,
            StickerPackPurchase.__table__,
            StickerFavorite.__table__,
            EmojiPack.__table__,
            CustomEmoji.__table__,
            EmojiPackInstall.__table__,
            EmojiPackPurchase.__table__,
            Conversation.__table__,
            ConversationMember.__table__,
            Message.__table__,
            MessageEditHistory.__table__,
            ScheduledMessage.__table__,
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


def test_marketplace_fee_waived_under_20():
    assert marketplace_fee_stars(19) == 0
    assert marketplace_fee_stars(20) >= 1
    assert marketplace_fee_stars(100) == 5


def test_preview_hides_custom_emoji_tokens():
    assert preview_text_with_custom_emoji("привет [[e:12]]") == "привет ✦"
    assert preview_text_with_custom_emoji("[[e:1]]") == "✦"
    assert preview_text_with_custom_emoji("   ") == "Сообщение"


def test_edit_and_schedule_require_custom_emoji(db_session):
    from datetime import datetime, timedelta, timezone

    from app.services.chat_service import ChatService

    seller = _user(db_session, 1)
    buyer = _user(db_session, 2)
    _activate(db_session, 1, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(seller.id, "Правка")
    item = emoji.add_emoji(
        user_id=seller.id,
        pack_id=pack.id,
        media_url="https://cdn.test/edit.webp",
    )
    db_session.commit()
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add_all(
        [
            ConversationMember(conversation_id=conv.id, user_id=seller.id),
            ConversationMember(conversation_id=conv.id, user_id=buyer.id),
        ]
    )
    msg = Message(
        conversation_id=conv.id,
        sender_id=buyer.id,
        type="text",
        content="привет",
    )
    db_session.add(msg)
    db_session.commit()
    chat = ChatService(db_session)
    token = f"[[e:{item.id}]]"
    with pytest.raises(ValueError, match="custom_emoji_required"):
        chat.edit_message(conv.id, msg.id, buyer.id, token)
    _activate(db_session, 2, 69)
    with pytest.raises(ValueError, match="custom_emoji_denied"):
        chat.edit_message(conv.id, msg.id, buyer.id, token)
    when = datetime.now(timezone.utc) + timedelta(hours=1)
    with pytest.raises(ValueError, match="custom_emoji_denied"):
        chat.schedule_message(
            conversation_id=conv.id,
            sender_id=buyer.id,
            msg_type="text",
            content=token,
            send_at=when,
        )


def test_emoji_catalog_includes_free_public(db_session):
    seller = _user(db_session, 1)
    _activate(db_session, 1, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(seller.id, "Бесплатный")
    emoji.add_emoji(
        user_id=seller.id,
        pack_id=pack.id,
        media_url="https://cdn.test/free.webp",
    )
    db_session.commit()
    assert emoji.list_marketplace() == []
    catalog = emoji.list_catalog()
    assert [p.id for p in catalog] == [pack.id]
    assert emoji.get_public_pack_by_slug(pack.slug) is not None


def test_resolve_hides_private_emoji(db_session):
    owner = _user(db_session, 1)
    stranger = _user(db_session, 2)
    _activate(db_session, 1, 70)
    emoji = EmojiPackService(db_session)
    public = emoji.create_pack(owner.id, "Публичный", True)
    private = emoji.create_pack(owner.id, "Личный", False)
    pub_item = emoji.add_emoji(
        user_id=owner.id,
        pack_id=public.id,
        media_url="https://cdn.test/pub.webp",
    )
    priv_item = emoji.add_emoji(
        user_id=owner.id,
        pack_id=private.id,
        media_url="https://cdn.test/priv.webp",
    )
    db_session.commit()
    rows = emoji.resolve_emojis([pub_item.id, priv_item.id])
    visible = {row.id for row in rows if emoji.can_view_emoji(stranger.id, row)}
    assert pub_item.id in visible
    assert priv_item.id not in visible
    assert emoji.can_view_emoji(owner.id, priv_item) is True
    assert emoji.can_use_emoji(stranger.id, pub_item) is False
    assert emoji.get_public_pack_by_slug(public.slug.upper()) is not None


def test_paid_sticker_send_needs_purchase(db_session):
    seller = _user(db_session, 1)
    buyer = _user(db_session, 2)
    _activate(db_session, 1, 71)
    stickers = StickerService(db_session)
    pack = stickers.create_pack(seller.id, "Платные", True)
    item = stickers.add_sticker(
        user_id=seller.id,
        pack_id=pack.id,
        media_url="https://cdn.test/paid.webp",
    )
    PackMarketplaceService(db_session).list_sticker_pack(seller.id, pack.id, 50)
    db_session.commit()
    with pytest.raises(ValueError, match="pack_purchase_required"):
        stickers.require_sticker_send(buyer.id, item.media_url)
    PaidFeaturesService(db_session).add_stars(buyer.id, 50, tx_type="admin_adjust")
    db_session.commit()
    PackMarketplaceService(db_session).buy_sticker_pack(buyer.id, pack.id)
    db_session.commit()
    stickers.require_sticker_send(buyer.id, item.media_url)
    stickers.uninstall_pack(buyer.id, pack.id)
    db_session.commit()
    mine = stickers.list_my_packs(buyer.id)
    assert any(p.id == pack.id for p in mine)
    stickers.require_sticker_send(buyer.id, item.media_url)


def test_reschedule_requires_custom_emoji_access(db_session):
    from datetime import datetime, timedelta, timezone

    from app.services.chat_service import ChatService

    seller = _user(db_session, 1)
    buyer = _user(db_session, 2)
    _activate(db_session, 1, 70)
    _activate(db_session, 2, 69)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(seller.id, "Отложено")
    item = emoji.add_emoji(
        user_id=seller.id,
        pack_id=pack.id,
        media_url="https://cdn.test/sched.webp",
    )
    db_session.commit()
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add_all(
        [
            ConversationMember(conversation_id=conv.id, user_id=seller.id),
            ConversationMember(conversation_id=conv.id, user_id=buyer.id),
        ]
    )
    db_session.commit()
    chat = ChatService(db_session)
    when = datetime.now(timezone.utc) + timedelta(hours=1)
    scheduled = chat.schedule_message(
        conversation_id=conv.id,
        sender_id=buyer.id,
        msg_type="text",
        content="позже",
        send_at=when,
    )
    db_session.commit()
    with pytest.raises(ValueError, match="custom_emoji_denied"):
        chat.reschedule_message(
            conversation_id=conv.id,
            scheduled_message_id=scheduled.id,
            user_id=buyer.id,
            content=f"[[e:{item.id}]]",
        )


def test_cannot_pin_uninstalled_sticker_pack(db_session):
    owner = _user(db_session, 1)
    stranger = _user(db_session, 2)
    _activate(db_session, 1, 71)
    stickers = StickerService(db_session)
    pack = stickers.create_pack(owner.id, "Закреп", True)
    stickers.add_sticker(
        user_id=owner.id,
        pack_id=pack.id,
        media_url="https://cdn.test/pin.webp",
    )
    db_session.commit()
    with pytest.raises(ValueError, match="pack_not_installed"):
        stickers.toggle_pinned_pack(user_id=stranger.id, pack_id=pack.id)
    assert stickers.replace_pinned_packs(user_id=stranger.id, pack_ids=[pack.id]) == []
    stickers.install_pack(stranger.id, pack.id)
    db_session.commit()
    ids, pinned = stickers.toggle_pinned_pack(user_id=stranger.id, pack_id=pack.id)
    assert pinned is True
    assert pack.id in ids


def test_emoji_pack_rename_and_reorder(db_session):
    owner = _user(db_session, 1)
    stranger = _user(db_session, 2)
    _activate(db_session, 1, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(owner.id, "Первый")
    a = emoji.add_emoji(user_id=owner.id, pack_id=pack.id, media_url="https://cdn.test/a.webp")
    b = emoji.add_emoji(user_id=owner.id, pack_id=pack.id, media_url="https://cdn.test/b.webp")
    db_session.commit()
    with pytest.raises(ValueError, match="forbidden"):
        emoji.update_pack(user_id=stranger.id, pack_id=pack.id, title="Чужой")
    updated = emoji.update_pack(user_id=owner.id, pack_id=pack.id, title="Второй", is_public=False)
    assert updated.title == "Второй"
    assert updated.is_public is False
    emoji.reorder_emojis(user_id=owner.id, pack_id=pack.id, emoji_ids=[b.id, a.id])
    db_session.commit()
    items = emoji.emojis_by_pack_ids([pack.id])[pack.id]
    assert [row.id for row in items] == [b.id, a.id]


def test_purchased_emoji_reinstall_after_private(db_session):
    seller = _user(db_session, 1)
    buyer = _user(db_session, 2)
    stranger = _user(db_session, 3)
    _activate(db_session, 1, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(seller.id, "После продажи")
    emoji.add_emoji(
        user_id=seller.id,
        pack_id=pack.id,
        media_url="https://cdn.test/sold.webp",
    )
    PackMarketplaceService(db_session).list_emoji_pack(seller.id, pack.id, 40)
    db_session.commit()
    PaidFeaturesService(db_session).add_stars(buyer.id, 40, tx_type="admin_adjust")
    db_session.commit()
    PackMarketplaceService(db_session).buy_emoji_pack(buyer.id, pack.id)
    db_session.commit()
    emoji.uninstall_pack(buyer.id, pack.id)
    emoji.update_pack(user_id=seller.id, pack_id=pack.id, is_public=False)
    db_session.commit()
    assert emoji.get_pack_for_user(buyer.id, pack.id) is not None
    assert emoji.get_pack_for_user(stranger.id, pack.id) is None
    with pytest.raises(ValueError, match="forbidden"):
        emoji.install_pack(stranger.id, pack.id)
    emoji.install_pack(buyer.id, pack.id)
    db_session.commit()
    assert emoji._is_installed(buyer.id, pack.id) is True


def test_purchased_sticker_reinstall_after_private(db_session):
    seller = _user(db_session, 1)
    buyer = _user(db_session, 2)
    stranger = _user(db_session, 3)
    _activate(db_session, 1, 71)
    stickers = StickerService(db_session)
    pack = stickers.create_pack(seller.id, "После продажи", True)
    stickers.add_sticker(
        user_id=seller.id,
        pack_id=pack.id,
        media_url="https://cdn.test/sold-sticker.webp",
    )
    PackMarketplaceService(db_session).list_sticker_pack(seller.id, pack.id, 50)
    db_session.commit()
    PaidFeaturesService(db_session).add_stars(buyer.id, 50, tx_type="admin_adjust")
    db_session.commit()
    PackMarketplaceService(db_session).buy_sticker_pack(buyer.id, pack.id)
    db_session.commit()
    stickers.uninstall_pack(buyer.id, pack.id)
    stickers.update_pack(user_id=seller.id, pack_id=pack.id, is_public=False)
    db_session.commit()
    assert stickers.get_pack_for_user(buyer.id, pack.id) is not None
    assert stickers.get_pack_for_user(stranger.id, pack.id) is None
    with pytest.raises(ValueError, match="forbidden"):
        stickers.install_pack(stranger.id, pack.id)
    stickers.install_pack(buyer.id, pack.id)
    db_session.commit()
    assert stickers._is_installed(buyer.id, pack.id) is True


def test_free_emoji_pack_install(db_session):
    owner = _user(db_session, 1)
    other = _user(db_session, 2)
    _activate(db_session, 1, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(owner.id, "Бесплатный пак", True)
    emoji.add_emoji(
        user_id=owner.id,
        pack_id=pack.id,
        media_url="https://cdn.test/free-install.webp",
    )
    db_session.commit()
    emoji.install_pack(other.id, pack.id)
    db_session.commit()
    assert emoji._is_installed(other.id, pack.id) is True


def test_purchased_emoji_access_survives_unlist(db_session):
    seller = _user(db_session, 1)
    buyer = _user(db_session, 2)
    stranger = _user(db_session, 3)
    _activate(db_session, 1, 70)
    _activate(db_session, 2, 69)
    _activate(db_session, 3, 69)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(seller.id, "Сняли с витрины")
    item = emoji.add_emoji(
        user_id=seller.id,
        pack_id=pack.id,
        media_url="https://cdn.test/unlist.webp",
    )
    market = PackMarketplaceService(db_session)
    market.list_emoji_pack(seller.id, pack.id, 40)
    db_session.commit()
    PaidFeaturesService(db_session).add_stars(buyer.id, 40, tx_type="admin_adjust")
    db_session.commit()
    market.buy_emoji_pack(buyer.id, pack.id)
    db_session.commit()
    emoji.uninstall_pack(buyer.id, pack.id)
    market.list_emoji_pack(seller.id, pack.id, 0)
    db_session.commit()
    assert int(pack.price_stars or 0) == 0
    assert market.has_emoji_access(buyer.id, pack) is True
    assert market.has_emoji_access(stranger.id, pack) is False
    emoji.require_send_tokens(buyer.id, f"[[e:{item.id}]]")
    emoji.install_pack(buyer.id, pack.id)
    db_session.commit()
    emoji.require_send_tokens(buyer.id, f"[[e:{item.id}]]")
    with pytest.raises(ValueError, match="custom_emoji_denied"):
        emoji.require_send_tokens(stranger.id, f"[[e:{item.id}]]")


def test_buy_rejects_stale_price(db_session):
    seller = _user(db_session, 1)
    buyer = _user(db_session, 2)
    _activate(db_session, 1, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(seller.id, "Дорожает")
    emoji.add_emoji(
        user_id=seller.id,
        pack_id=pack.id,
        media_url="https://cdn.test/price.webp",
    )
    market = PackMarketplaceService(db_session)
    market.list_emoji_pack(seller.id, pack.id, 40)
    db_session.commit()
    PaidFeaturesService(db_session).add_stars(buyer.id, 80, tx_type="admin_adjust")
    db_session.commit()
    market.list_emoji_pack(seller.id, pack.id, 80)
    db_session.commit()
    with pytest.raises(HTTPException) as err:
        market.buy_emoji_pack(buyer.id, pack.id, expected_price_stars=40)
    assert err.value.status_code == 409
    assert err.value.detail["code"] == "price_changed"
    market.buy_emoji_pack(buyer.id, pack.id, expected_price_stars=80)
    db_session.commit()
    assert PaidFeaturesService(db_session).star_balance(buyer.id) == 0


def test_slug_opens_purchased_private_pack(db_session):
    seller = _user(db_session, 1)
    buyer = _user(db_session, 2)
    stranger = _user(db_session, 3)
    _activate(db_session, 1, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(seller.id, "Ссылка")
    emoji.add_emoji(
        user_id=seller.id,
        pack_id=pack.id,
        media_url="https://cdn.test/slug.webp",
    )
    market = PackMarketplaceService(db_session)
    market.list_emoji_pack(seller.id, pack.id, 25)
    db_session.commit()
    PaidFeaturesService(db_session).add_stars(buyer.id, 25, tx_type="admin_adjust")
    db_session.commit()
    market.buy_emoji_pack(buyer.id, pack.id)
    db_session.commit()
    emoji.update_pack(user_id=seller.id, pack_id=pack.id, is_public=False)
    db_session.commit()
    assert emoji.get_pack_by_slug_for_user(buyer.id, pack.slug) is not None
    assert emoji.get_pack_by_slug_for_user(stranger.id, pack.slug) is None
    assert emoji.get_public_pack_by_slug(pack.slug) is None


def test_cannot_favorite_paid_sticker_without_purchase(db_session):
    seller = _user(db_session, 1)
    buyer = _user(db_session, 2)
    _activate(db_session, 1, 71)
    stickers = StickerService(db_session)
    pack = stickers.create_pack(seller.id, "Избранное", True)
    item = stickers.add_sticker(
        user_id=seller.id,
        pack_id=pack.id,
        media_url="https://cdn.test/fav.webp",
    )
    PackMarketplaceService(db_session).list_sticker_pack(seller.id, pack.id, 40)
    db_session.commit()
    with pytest.raises(ValueError, match="pack_purchase_required"):
        stickers.toggle_favorite(user_id=buyer.id, sticker_id=item.id)
    PaidFeaturesService(db_session).add_stars(buyer.id, 40, tx_type="admin_adjust")
    db_session.commit()
    PackMarketplaceService(db_session).buy_sticker_pack(buyer.id, pack.id)
    db_session.commit()
    _, favorited = stickers.toggle_favorite(user_id=buyer.id, sticker_id=item.id)
    assert favorited is True


def test_list_favorites_hides_unpurchased_paid(db_session):
    seller = _user(db_session, 1)
    buyer = _user(db_session, 2)
    _activate(db_session, 1, 71)
    stickers = StickerService(db_session)
    pack = stickers.create_pack(seller.id, "Скрытое избранное", True)
    item = stickers.add_sticker(
        user_id=seller.id,
        pack_id=pack.id,
        media_url="https://cdn.test/fav-hidden.webp",
    )
    PackMarketplaceService(db_session).list_sticker_pack(seller.id, pack.id, 40)
    db_session.add(StickerFavorite(user_id=buyer.id, sticker_id=item.id))
    db_session.commit()
    assert stickers.list_favorites(buyer.id) == []
    PaidFeaturesService(db_session).add_stars(buyer.id, 40, tx_type="admin_adjust")
    db_session.commit()
    PackMarketplaceService(db_session).buy_sticker_pack(buyer.id, pack.id)
    db_session.commit()
    assert [row.id for row in stickers.list_favorites(buyer.id)] == [item.id]


def test_uninstall_clears_status_without_license(db_session):
    owner = _user(db_session, 1)
    other = _user(db_session, 2)
    _activate(db_session, 1, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(owner.id, "Статус бесплатный", True)
    item = emoji.add_emoji(
        user_id=owner.id,
        pack_id=pack.id,
        media_url="https://cdn.test/status-free.webp",
    )
    db_session.commit()
    emoji.install_pack(other.id, pack.id)
    other.emoji_status = f"ce:{item.id}"
    db_session.commit()
    emoji.uninstall_pack(other.id, pack.id)
    db_session.commit()
    db_session.refresh(other)
    assert other.emoji_status is None


def test_uninstall_keeps_purchased_status(db_session):
    seller = _user(db_session, 1)
    buyer = _user(db_session, 2)
    _activate(db_session, 1, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(seller.id, "Статус купленный")
    item = emoji.add_emoji(
        user_id=seller.id,
        pack_id=pack.id,
        media_url="https://cdn.test/status-paid.webp",
    )
    PackMarketplaceService(db_session).list_emoji_pack(seller.id, pack.id, 25)
    db_session.commit()
    PaidFeaturesService(db_session).add_stars(buyer.id, 25, tx_type="admin_adjust")
    db_session.commit()
    PackMarketplaceService(db_session).buy_emoji_pack(buyer.id, pack.id)
    db_session.commit()
    buyer.emoji_status = f"ce:{item.id}"
    db_session.commit()
    emoji.uninstall_pack(buyer.id, pack.id)
    db_session.commit()
    db_session.refresh(buyer)
    assert buyer.emoji_status == f"ce:{item.id}"


def test_visible_status_hides_custom_without_flex(db_session):
    owner = _user(db_session, 1)
    _activate(db_session, 1, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(owner.id, "Статус на профиле", True)
    item = emoji.add_emoji(
        user_id=owner.id,
        pack_id=pack.id,
        media_url="https://cdn.test/status-flex.webp",
    )
    owner.emoji_status = f"ce:{item.id}"
    db_session.commit()
    assert emoji.visible_emoji_status(owner) == f"ce:{item.id}"
    FlexSubscriptionService(db_session).deactivate(1)
    db_session.commit()
    db_session.refresh(owner)
    assert owner.emoji_status == f"ce:{item.id}"
    assert emoji.visible_emoji_status(owner) is None
    _activate(db_session, 1, 69)
    db_session.commit()
    db_session.refresh(owner)
    assert emoji.visible_emoji_status(owner) == f"ce:{item.id}"


def test_visible_status_keeps_unicode(db_session):
    user = _user(db_session, 1)
    user.emoji_status = "🔥"
    db_session.commit()
    assert EmojiPackService(db_session).visible_emoji_status(user) == "🔥"


def test_failed_scheduled_sticker_stays_listed(db_session):
    from datetime import datetime, timezone

    from app.services.chat_service import ChatService

    seller = _user(db_session, 1)
    buyer = _user(db_session, 2)
    conv = Conversation(type="direct", title="ЛС")
    db_session.add(conv)
    db_session.flush()
    db_session.add_all(
        [
            ConversationMember(conversation_id=conv.id, user_id=seller.id),
            ConversationMember(conversation_id=conv.id, user_id=buyer.id),
        ]
    )
    when = datetime.now(timezone.utc).replace(tzinfo=None)
    db_session.add(
        ScheduledMessage(
            conversation_id=conv.id,
            sender_id=buyer.id,
            type="sticker",
            content="",
            media_url="https://cdn.test/sched-sticker.webp",
            send_at=when,
            status="failed",
            error_text=ChatService._scheduled_fail_text("pack_purchase_required"),
        )
    )
    db_session.commit()
    chat = ChatService(db_session)
    listed = chat.list_scheduled_messages(conv.id, buyer.id)
    assert len(listed) == 1
    assert listed[0].status == "failed"
    assert listed[0].error_text == "Нужно купить пак"

    from datetime import timedelta

    later = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(hours=2)
    retried = chat.reschedule_message(conv.id, listed[0].id, buyer.id, send_at=later)
    assert retried.status == "pending"
    assert retried.error_text is None

    failed = ScheduledMessage(
        conversation_id=conv.id,
        sender_id=buyer.id,
        type="sticker",
        content="",
        media_url="https://cdn.test/sched-sticker-2.webp",
        send_at=when,
        status="failed",
        error_text=ChatService._scheduled_fail_text("pack_purchase_required"),
    )
    db_session.add(failed)
    db_session.commit()
    db_session.refresh(failed)
    canceled = chat.cancel_scheduled_message(conv.id, failed.id, buyer.id)
    assert canceled.status == "canceled"
    left = chat.list_scheduled_messages(conv.id, buyer.id)
    assert [item.id for item in left] == [retried.id]


def test_flex_loss_unlists_priced_packs(db_session):
    seller = _user(db_session, 1)
    _activate(db_session, 1, 72)
    stickers = StickerService(db_session)
    emoji = EmojiPackService(db_session)
    market = PackMarketplaceService(db_session)
    pack = stickers.create_pack(seller.id, "Стикеры с витрины", True)
    stickers.add_sticker(
        user_id=seller.id,
        pack_id=pack.id,
        media_url="https://cdn.test/unlist-sticker.webp",
    )
    market.list_sticker_pack(seller.id, pack.id, 80)
    ep = emoji.create_pack(seller.id, "Эмодзи с витрины")
    emoji.add_emoji(
        user_id=seller.id,
        pack_id=ep.id,
        media_url="https://cdn.test/unlist-emoji.webp",
    )
    market.list_emoji_pack(seller.id, ep.id, 30)
    db_session.commit()
    FlexSubscriptionService(db_session).deactivate(1)
    db_session.commit()
    db_session.refresh(pack)
    db_session.refresh(ep)
    assert pack.price_stars == 80
    assert ep.price_stars == 30
    assert emoji.list_marketplace() == []
    assert stickers.list_marketplace_packs() == []
    assert emoji.list_catalog() == []
    assert stickers.list_catalog_packs(user_id=seller.id) == []
    assert market.is_actively_listed(pack, kind="sticker") is False
    assert market.is_actively_listed(ep, kind="emoji") is False
    buyer = _user(db_session, 2)
    PaidFeaturesService(db_session).add_stars(buyer.id, 80, tx_type="admin_adjust")
    db_session.commit()
    with pytest.raises(HTTPException) as err:
        market.buy_sticker_pack(buyer.id, pack.id)
    assert err.value.status_code == 400
    _activate(db_session, 1, 72)
    db_session.commit()
    assert any(row.id == ep.id for row in emoji.list_marketplace())


def test_keep_listing_on_higher_level(db_session):
    seller = _user(db_session, 1)
    _activate(db_session, 1, 71)
    stickers = StickerService(db_session)
    pack = stickers.create_pack(seller.id, "Остаётся в продаже", True)
    stickers.add_sticker(
        user_id=seller.id,
        pack_id=pack.id,
        media_url="https://cdn.test/keep-listed.webp",
    )
    PackMarketplaceService(db_session).list_sticker_pack(seller.id, pack.id, 60)
    db_session.commit()
    _activate(db_session, 1, 72)
    db_session.commit()
    db_session.refresh(pack)
    assert pack.price_stars == 60


def test_suggested_post_requires_custom_emoji_access(db_session):
    seller = _user(db_session, 1)
    stranger = _user(db_session, 3)
    _activate(db_session, 1, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(seller.id, "Совет")
    item = emoji.add_emoji(
        user_id=seller.id,
        pack_id=pack.id,
        media_url="https://cdn.test/suggest.webp",
    )
    db_session.commit()
    token = f"привет [[e:{item.id}]]"
    with pytest.raises(HTTPException) as err:
        PaidFeaturesService(db_session).suggest_channel_post(
            stranger.id,
            999,
            text=token,
            amount_stars=10,
        )
    assert err.value.status_code == 403
    _activate(db_session, 1, 69)
    with pytest.raises(HTTPException) as allowed:
        PaidFeaturesService(db_session).suggest_channel_post(
            seller.id,
            999,
            text=token,
            amount_stars=10,
        )
    assert allowed.value.status_code == 404
