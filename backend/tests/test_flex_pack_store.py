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
    ConversationDraft,
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
from app.models.user_business import UserBusinessSettings
from app.models.chat_folder import ChatFolder, ChatFolderItem
from app.models.chat_folder_share import ChatFolderShare
from app.models.forum_topic import ForumTopic
from app.models.saved_tag import SavedTag
from app.models.story import Story, StoryReaction
from app.models.quick_reply import QuickReply
from app.services.emoji_pack_service import (
    EmojiPackService,
    authored_or_peer_label,
    authored_send_texts,
    avatar_letter_with_custom_emoji,
    clip_preserving_custom_emoji,
    display_name_or_default,
    editor_or_preview_tokens,
    keep_if_unchanged,
    keep_if_unchanged_http,
    keep_if_unchanged_items,
    keep_or_preview_tokens,
    link_preview_for_persist,
    link_preview_for_persist_http,
    prepare_forward_content,
    preview_text_with_custom_emoji,
    split_hanwe_share,
    text_for_moderation,
    text_for_translation,
)
from app.services.flex_subscription_service import FlexSubscriptionService
from app.services.chat_service import ChatService
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
            ConversationDraft.__table__,
            Message.__table__,
            MessageEditHistory.__table__,
            ScheduledMessage.__table__,
            UserBusinessSettings.__table__,
            ChatFolder.__table__,
            ChatFolderItem.__table__,
            ChatFolderShare.__table__,
            ForumTopic.__table__,
            SavedTag.__table__,
            Story.__table__,
            StoryReaction.__table__,
            QuickReply.__table__,
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


def test_avatar_letter_skips_custom_emoji_tokens():
    assert avatar_letter_with_custom_emoji("") == "?"
    assert avatar_letter_with_custom_emoji("   ") == "?"
    assert avatar_letter_with_custom_emoji("[[e:12]]") == "✦"
    assert avatar_letter_with_custom_emoji("[[e:12]] Иван") == "И"
    assert avatar_letter_with_custom_emoji("привет") == "П"


def test_poll_preview_hides_custom_emoji_tokens():
    import json

    from app.services.chat_poll_service import poll_preview_text

    content = json.dumps({"poll": {"question": "еда [[e:12]]?"}}, ensure_ascii=False)
    preview = poll_preview_text(content)
    assert "[[e:" not in preview
    assert "✦" in preview


def test_require_reaction_http_needs_level_72(db_session):
    seller = _user(db_session, 1)
    _activate(db_session, 1, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(seller.id, "Реакция")
    item = emoji.add_emoji(
        user_id=seller.id,
        pack_id=pack.id,
        media_url="https://cdn.test/react.webp",
    )
    db_session.commit()
    with pytest.raises(HTTPException) as err:
        emoji.require_reaction_http(seller.id, f"ce:{item.id}")
    assert err.value.status_code == 403
    _activate(db_session, 1, 72)
    assert emoji.require_reaction_http(seller.id, f"ce:{item.id}") == f"ce:{item.id}"


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
    EmojiPackService(db_session).require_send_tokens_http(seller.id, token)


def test_invoice_and_giveaway_require_custom_emoji(db_session):
    owner = _user(db_session, 1)
    _activate(db_session, 1, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(owner.id, "Счёт")
    item = emoji.add_emoji(
        user_id=owner.id,
        pack_id=pack.id,
        media_url="https://cdn.test/invoice.webp",
    )
    db_session.commit()
    token = f"приз [[e:{item.id}]]"
    _activate(db_session, 1, 10)
    with pytest.raises(HTTPException) as err:
        PaidFeaturesService(db_session).create_star_giveaway(
            owner.id,
            1,
            prize_stars=10,
            winners_count=1,
            duration_hours=1,
            title=token,
        )
    assert err.value.status_code == 403
    bot = User(
        id=10,
        email="bot@t.test",
        password_hash="h",
        name="Bot",
        is_bot=True,
        created_by_user_id=owner.id,
    )
    db_session.add(bot)
    db_session.commit()
    with pytest.raises(HTTPException) as invoice_err:
        PaidFeaturesService(db_session).create_star_invoice(
            owner.id,
            bot.id,
            title=token,
            amount_stars=10,
        )
    assert invoice_err.value.status_code == 403


def _emoji_token_after_downgrade(db, user_id: int) -> str:
    _activate(db, user_id, 70)
    emoji = EmojiPackService(db)
    pack = emoji.create_pack(user_id, "Гейт")
    item = emoji.add_emoji(
        user_id=user_id,
        pack_id=pack.id,
        media_url="https://cdn.test/gate.webp",
    )
    db.commit()
    token = f"имя [[e:{item.id}]]"
    _activate(db, user_id, 10)
    return token


def test_folder_name_requires_custom_emoji(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji_required"):
        ChatService(db_session).create_folder(owner.id, token)


def test_forum_topic_title_requires_custom_emoji(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji_required"):
        ChatService(db_session).create_forum_topic(999, owner.id, token)


def test_group_title_requires_custom_emoji(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji_required"):
        ChatService(db_session).create_group(owner.id, token, [])


def test_donate_note_requires_custom_emoji(db_session):
    sender = _user(db_session, 1)
    recipient = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, sender.id)
    with pytest.raises(HTTPException) as err:
        PaidFeaturesService(db_session).donate(
            sender.id,
            recipient.id,
            1,
            message=token,
        )
    assert err.value.status_code == 403


def test_sticker_pack_title_requires_custom_emoji(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji_required"):
        StickerService(db_session).create_pack(owner.id, token, True)


def test_emoji_pack_title_requires_custom_emoji(db_session):
    owner = _user(db_session, 1)
    _activate(db_session, 1, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(owner.id, "Пак")
    item = emoji.add_emoji(
        user_id=owner.id,
        pack_id=pack.id,
        media_url="https://cdn.test/title.webp",
    )
    db_session.commit()
    token = f"имя [[e:{item.id}]]"
    _activate(db_session, 1, 10)
    with pytest.raises(ValueError, match="custom_emoji_required"):
        emoji.update_pack(user_id=owner.id, pack_id=pack.id, title=token)


def test_moderation_reason_requires_custom_emoji(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji_required"):
        ChatService(db_session).ban_group_member(
            999,
            owner.id,
            2,
            reason=token,
            banned_until=None,
        )
    with pytest.raises(ValueError, match="custom_emoji_required"):
        ChatService(db_session).set_group_member_send_restriction(
            999,
            owner.id,
            2,
            send_restricted=True,
            send_restricted_until=None,
            reason=token,
        )


def test_checklist_and_file_preview_hide_custom_emoji_tokens():
    from app.services.chat_checklist_service import checklist_preview_text

    raw = (
        '{"checklist":{"title":"еда [[e:12]]","items":'
        '[{"text":"a","done":false}]}}'
    )
    preview = checklist_preview_text(raw)
    assert "[[e:" not in preview
    assert "✦" in preview

    class _Msg:
        type = "file"
        content = "отчет [[e:9]].pdf"

    file_preview = ChatService(None)._message_preview_text(_Msg())
    assert "[[e:" not in file_preview
    assert "✦" in file_preview


def test_file_preview_blank_name_is_file_not_soobshenie():
    class _Msg:
        type = "file"
        content = "   "

    assert ChatService(None)._message_preview_text(_Msg()) == "📎 Файл"


def test_display_name_or_default_skips_soobshenie():
    assert display_name_or_default("   ", default="Звонок") == "Звонок"
    assert display_name_or_default("", default="Пользователь") == "Пользователь"
    assert display_name_or_default("еда [[e:12]]", default="Звонок") == "еда ✦"


def test_report_comment_requires_custom_emoji(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    from app.services.content_report_service import ContentReportService

    with pytest.raises(HTTPException) as err:
        ContentReportService(db_session).create_report(
            content_type="post",
            content_id=1,
            reporter_user_id=owner.id,
            reason="spam",
            comment=token,
        )
    assert err.value.status_code == 403


def test_payout_note_requires_custom_emoji(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(HTTPException) as err:
        PaidFeaturesService(db_session).request_creator_payout(
            owner.id,
            10,
            note=token,
        )
    assert err.value.status_code == 403


def test_channel_push_title_hides_custom_emoji_tokens():
    from app.services.emoji_pack_service import preview_text_with_custom_emoji

    title = f"Новый пост в канале {preview_text_with_custom_emoji('еда [[e:12]]', limit=80)}"
    assert "[[e:" not in title
    assert "✦" in title


def test_strip_custom_emoji_tokens_for_imported_names():
    from app.services.emoji_pack_service import strip_custom_emoji_tokens

    assert strip_custom_emoji_tokens("Анна [[e:12]] Иванова") == "Анна Иванова"
    assert strip_custom_emoji_tokens("[[e:1]]") == ""
    assert strip_custom_emoji_tokens(None) == ""
    assert strip_custom_emoji_tokens("  Google User  ") == "Google User"


def test_review_payout_note_requires_custom_emoji(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(HTTPException) as err:
        PaidFeaturesService(db_session).review_payout(
            999,
            reviewer_user_id=owner.id,
            approve=True,
            note=token,
        )
    assert err.value.status_code == 403


def test_signup_name_tokens_require_custom_emoji(db_session):
    owner = _user(db_session, 1)
    with pytest.raises(HTTPException) as err:
        EmojiPackService(db_session).require_send_tokens_http(
            owner.id,
            "Иван [[e:7]]",
        )
    assert err.value.status_code == 403


def test_draft_requires_custom_emoji(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji_required"):
        ChatService(db_session).upsert_draft(1, owner.id, token)


def test_draft_share_subject_does_not_403_without_flex(db_session):
    author = _user(db_session, 1)
    sender = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, author.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add(ConversationMember(conversation_id=conv.id, user_id=sender.id))
    db_session.commit()
    text = f"Пост {token}\n\nОткрыть в HanWe: https://haneat.app/post/7"
    row = ChatService(db_session).upsert_draft(conv.id, sender.id, text)
    db_session.commit()
    assert "[[e:" not in (row.text or "")
    assert "✦" in (row.text or "")
    assert "https://haneat.app/post/7" in (row.text or "")


def test_draft_private_reply_header_does_not_403_without_flex(db_session):
    author = _user(db_session, 1)
    sender = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, author.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add(ConversationMember(conversation_id=conv.id, user_id=sender.id))
    db_session.commit()
    row = ChatService(db_session).upsert_draft(
        conv.id, sender.id, f"↩️ {token}: {token}\n\nОк"
    )
    db_session.commit()
    assert "[[e:" not in (row.text or "")
    assert "✦" in (row.text or "")
    assert (row.text or "").endswith("Ок")


def test_draft_contact_card_does_not_403_without_flex(db_session):
    peer = _user(db_session, 1)
    sender = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, peer.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add(ConversationMember(conversation_id=conv.id, user_id=sender.id))
    db_session.commit()
    row = ChatService(db_session).upsert_draft(
        conv.id, sender.id, f"👤 Контакт\n{token}\n@peer"
    )
    db_session.commit()
    assert "[[e:" not in (row.text or "")
    assert "Контакт" in (row.text or "")


def test_draft_share_body_tokens_still_require_flex(db_session):
    sender = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, sender.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add(ConversationMember(conversation_id=conv.id, user_id=sender.id))
    db_session.commit()
    with pytest.raises(ValueError, match="custom_emoji_required"):
        ChatService(db_session).upsert_draft(
            conv.id,
            sender.id,
            f"Пост\n\nОткрыть в HanWe: https://haneat.app/post/7\n{token}",
        )


def test_emoji_shortcode_requires_custom_emoji(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji_required"):
        EmojiPackService(db_session).add_emoji(
            user_id=owner.id,
            pack_id=1,
            media_url="https://cdn.test/x.webp",
            shortcode=token,
        )


def test_sticker_emoji_requires_custom_emoji(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji_required"):
        StickerService(db_session).add_sticker(
            user_id=owner.id,
            pack_id=1,
            media_url="https://cdn.test/x.webp",
            emoji=token,
        )


def test_miniapp_moderation_note_requires_custom_emoji(db_session):
    import asyncio

    from app.api.v1.miniapps import MiniAppModerationRequest, moderate_miniapp

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await moderate_miniapp(
            1,
            MiniAppModerationRequest(
                moderation_status="approved",
                moderation_note=token,
            ),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    assert err.value.status_code == 403


def test_moderation_comment_requires_custom_emoji(db_session):
    import asyncio

    from app.api.v1.moderation import ApproveRequest, approve_content

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await approve_content(
            1,
            ApproveRequest(comment=token),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    assert err.value.status_code == 403


def test_moderation_reject_reason_requires_custom_emoji(db_session):
    import asyncio

    from app.api.v1.moderation import RejectRequest, reject_content

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await reject_content(
            1,
            RejectRequest(reason=token, comment=None),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    assert err.value.status_code == 403


def test_moderation_warn_message_requires_custom_emoji(db_session):
    import asyncio

    from app.api.v1.moderation import WarnUserRequest, warn_user

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await warn_user(
            2,
            WarnUserRequest(message=token),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    assert err.value.status_code == 403


def test_moderation_ban_reason_requires_custom_emoji(db_session):
    import asyncio

    from app.api.v1.moderation import BanUserRequest, ban_user

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await ban_user(
            2,
            BanUserRequest(reason=token),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    assert err.value.status_code == 403


def test_community_author_does_not_require_custom_emoji(db_session):
    import asyncio

    from app.api.v1.community_upload import (
        CommunityUploadRequest,
        upload_community_video,
    )

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await upload_community_video(
            CommunityUploadRequest(
                title="Рилс",
                author=token,
                description="ок",
            ),
            request=None,
            current_user=owner,
            db=db_session,
        )

    # Author is a prefilled channel/profile name — 400 (no video), not 403 flex.
    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    assert err.value.status_code == 400
    assert "custom_emoji" not in str(err.value.detail)


def test_forum_topic_icon_requires_custom_emoji(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji_required"):
        ChatService(db_session).create_forum_topic(
            1,
            owner.id,
            title="Тема",
            icon_emoji=token,
        )


def test_folder_icon_requires_custom_emoji(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji_required"):
        ChatService(db_session).create_folder(
            owner.id,
            name="Папка",
            icon=token,
        )


def test_folder_icon_update_requires_custom_emoji(db_session):
    owner = _user(db_session, 1)
    chats = ChatService(db_session)
    folder = chats.create_folder(owner.id, "Папка")
    db_session.commit()
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji_required"):
        chats.update_folder(owner.id, folder["id"], icon=token)


def test_post_tags_require_custom_emoji(db_session):
    import asyncio

    from app.api.v1.posts import create_post
    from app.schemas.post import CreatePostRequest

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await create_post(
            CreatePostRequest(type="text", tags=[token]),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    assert err.value.status_code == 403


def test_post_tag_update_requires_custom_emoji(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    # Fixture has no Post table — author update uses this helper after lookup.
    emoji = EmojiPackService(db_session)
    with pytest.raises(HTTPException) as err:
        keep_if_unchanged_items(
            emoji, owner.id, [token], ["новости"], http=True
        )
    assert err.value.status_code == 403


def test_community_tag_requires_custom_emoji(db_session):
    import asyncio

    from app.api.v1.community_upload import (
        CommunityUploadRequest,
        upload_community_video,
    )

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await upload_community_video(
            CommunityUploadRequest(
                title="Рилс",
                author="Автор",
                description="ок",
                tags=[token],
            ),
            request=None,
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    assert err.value.status_code == 403


def test_support_resolution_requires_custom_emoji(db_session):
    import asyncio

    from app.api.v1.support import ResolveTicketRequest, resolve_ticket

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await resolve_ticket(
            1,
            ResolveTicketRequest(resolution_comment=token),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    assert err.value.status_code == 403


def test_channel_category_requires_custom_emoji(db_session):
    import asyncio

    from app.api.v1.channels import create_channel
    from app.schemas.channel import CreateChannelRequest

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await create_channel(
            CreateChannelRequest(
                name="Кухня",
                slug="kitchen",
                category=token,
            ),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    assert err.value.status_code == 403


def test_channel_update_category_requires_custom_emoji(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    # Owner path of update_channel uses this helper after the Channel lookup.
    # Fixture has no channels table — do not call update_channel here.
    with pytest.raises(HTTPException) as err:
        EmojiPackService(db_session).require_send_tokens_http(
            owner.id, None, None, None, token
        )
    assert err.value.status_code == 403


def test_cancel_subscription_reason_requires_custom_emoji(db_session):
    import asyncio

    from app.api.v1.subscriptions import CancelSubscriptionRequest, cancel_subscription

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await cancel_subscription(
            CancelSubscriptionRequest(cancellation_reason=token),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    assert err.value.status_code == 403


def test_channel_share_text_hides_custom_emoji_tokens():
    from app.services.emoji_pack_service import preview_text_with_custom_emoji

    title = preview_text_with_custom_emoji("Кухня [[e:12]]")
    assert "[[e:" not in title
    assert "✦" in title


def test_create_post_title_requires_custom_emoji(db_session):
    import asyncio

    from app.api.v1.posts import create_post
    from app.schemas.post import CreatePostRequest

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await create_post(
            CreatePostRequest(type="text", title=token),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    assert err.value.status_code == 403


def test_update_post_title_requires_custom_emoji(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    # Fixture has no Post table — author update uses this helper after lookup.
    emoji = EmojiPackService(db_session)
    with pytest.raises(HTTPException) as err:
        keep_if_unchanged_http(emoji, owner.id, token, "Заголовок")
    assert err.value.status_code == 403


def test_create_quick_reply_requires_custom_emoji(db_session):
    import asyncio

    from app.api.v1.chats import create_quick_reply

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await create_quick_reply(
            {"title": token, "text": "ок"},
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    assert err.value.status_code == 403


def test_create_chat_tag_requires_custom_emoji(db_session):
    import asyncio

    from app.api.v1.chats import create_chat_tag
    from app.schemas.chat import CreateChatTagRequest

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await create_chat_tag(
            CreateChatTagRequest(title=token),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    assert err.value.status_code == 403


def test_inline_keyboard_text_requires_custom_emoji(db_session):
    import json

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    keyboard = json.dumps([[{"text": token, "callback_data": "ok"}]])
    with pytest.raises(ValueError, match="custom_emoji_required"):
        ChatService(db_session).send_message(
            conversation_id=1,
            sender_id=owner.id,
            msg_type="text",
            content="ок",
            inline_keyboard_json=keyboard,
        )


def test_schedule_inline_keyboard_text_requires_custom_emoji(db_session):
    import json
    from datetime import datetime, timedelta, timezone

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    keyboard = json.dumps([[{"text": token, "callback_text": "нажал"}]])
    with pytest.raises(ValueError, match="custom_emoji_required"):
        ChatService(db_session).schedule_message(
            conversation_id=1,
            sender_id=owner.id,
            msg_type="text",
            content="ок",
            send_at=datetime.now(timezone.utc) + timedelta(hours=1),
            inline_keyboard_json=keyboard,
        )


def test_bot_owner_text_previews_after_downgrade(db_session):
    from types import SimpleNamespace

    from app.services.bot_handler import _text_for_bot_owner

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    bot = SimpleNamespace(created_by_user_id=owner.id)
    out = _text_for_bot_owner(db_session, bot, token)
    assert "[[e:" not in out
    assert "✦" in out


def test_bot_owner_keyboard_previews_after_downgrade(db_session):
    from types import SimpleNamespace

    from app.services.bot_handler import _keyboard_for_bot_owner

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    bot = SimpleNamespace(created_by_user_id=owner.id)
    out = _keyboard_for_bot_owner(
        db_session,
        bot,
        [[{"text": token, "callback_text": token, "callback_data": "x"}]],
    )
    assert out is not None
    assert "[[e:" not in out[0][0]["text"]
    assert "[[e:" not in out[0][0]["callback_text"]


def test_business_auto_text_previews_after_downgrade(db_session):
    from app.services.business_profile_service import _auto_text_for_sender

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    out = _auto_text_for_sender(db_session, owner.id, token)
    assert "[[e:" not in out
    assert "✦" in out


def test_business_auto_text_keeps_long_preview_after_downgrade(db_session):
    from app.services.business_profile_service import _auto_text_for_sender

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    long = ("Привет, это длинное приветствие бизнеса. " * 8) + token
    assert len(long) > 120
    out = _auto_text_for_sender(db_session, owner.id, long)
    assert "[[e:" not in out
    assert "✦" in out
    assert len(out) > 120
    assert out.startswith("Привет")


def test_bot_owner_text_keeps_long_preview_after_downgrade(db_session):
    from types import SimpleNamespace

    from app.services.bot_handler import _text_for_bot_owner

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    bot = SimpleNamespace(created_by_user_id=owner.id)
    long = ("Ответ бота после даунгрейда владельца. " * 8) + token
    assert len(long) > 120
    out = _text_for_bot_owner(db_session, bot, long)
    assert "[[e:" not in out
    assert "✦" in out
    assert len(out) > 120
    assert out.startswith("Ответ бота")


def test_create_repost_comment_requires_custom_emoji(db_session):
    import asyncio

    from app.api.v1.reposts import CreateRepostRequest, create_repost

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await create_repost(
            1,
            CreateRepostRequest(comment=token),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    assert err.value.status_code == 403


def test_user_label_hides_custom_emoji_tokens():
    from types import SimpleNamespace

    from app.api.v1.chats import _user_label

    user = SimpleNamespace(id=1, name="Анна [[e:12]]", username="anna")
    out = _user_label(user)
    assert "[[e:" not in out
    assert "✦" in out


def test_channel_last_post_preview_hides_custom_emoji_tokens():
    from types import SimpleNamespace

    from app.api.v1.channels import _post_preview_text

    post = SimpleNamespace(title="Кухня [[e:12]]", description="", type="text")
    out = _post_preview_text(post)
    assert "[[e:" not in out
    assert "✦" in out


def test_channel_last_post_preview_empty_title_uses_description():
    from types import SimpleNamespace

    from app.api.v1.channels import _post_preview_text

    post = SimpleNamespace(title="", description="Рилс про суп [[e:12]]", type="reel")
    out = _post_preview_text(post)
    assert out.startswith("Рилс про суп")
    assert "[[e:" not in out
    assert out != "Сообщение"


def test_channel_last_post_preview_empty_falls_back_to_type():
    from types import SimpleNamespace

    from app.api.v1.channels import _post_preview_text

    post = SimpleNamespace(title="", description="", type="reel")
    assert _post_preview_text(post) == "Видео"


def test_translate_previews_tokens_without_flex(db_session):
    import asyncio

    from app.api.v1.chats import translate_chat_text
    from app.schemas.chat import TranslateTextRequest

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    # Translation is reading — block C (level 16) is enough; do not 403 on 69.
    _activate(db_session, owner.id, 16)

    async def _run():
        return await translate_chat_text(
            TranslateTextRequest(text=token, target_lang="en"),
            current_user=owner,
            db=db_session,
        )

    out = asyncio.run(_run())
    assert "[[e:" not in out.translated
    assert "✦" in out.translated


def test_keep_or_preview_tokens_without_flex(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    out = keep_or_preview_tokens(EmojiPackService(db_session), owner.id, token)
    assert "[[e:" not in (out or "")
    assert "✦" in (out or "")


def test_keep_or_preview_tokens_keeps_when_allowed(db_session):
    owner = _user(db_session, 1)
    _activate(db_session, owner.id, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(owner.id, "Превью")
    item = emoji.add_emoji(
        user_id=owner.id,
        pack_id=pack.id,
        media_url="https://cdn.test/keep.webp",
    )
    db_session.commit()
    token = f"имя [[e:{item.id}]]"
    assert keep_or_preview_tokens(emoji, owner.id, token) == token


def test_authored_or_peer_label_previews_default_name(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    viewer = _user(db_session, 2)
    _activate(db_session, viewer.id, 10)
    emoji = EmojiPackService(db_session)
    out = authored_or_peer_label(
        emoji, viewer.id, None, token, default="Mini App", limit=64
    )
    assert "[[e:" not in out
    assert "✦" in out


def test_authored_or_peer_label_gates_own_button(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji"):
        authored_or_peer_label(
            EmojiPackService(db_session),
            owner.id,
            token,
            "Mini App",
            default="Mini App",
            limit=64,
        )


def test_editor_or_preview_tokens_gates_own(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji"):
        editor_or_preview_tokens(
            EmojiPackService(db_session), owner.id, token, own=True
        )


def test_editor_or_preview_tokens_previews_peer(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    editor = _user(db_session, 2)
    _activate(db_session, editor.id, 10)
    out = editor_or_preview_tokens(
        EmojiPackService(db_session), editor.id, token, own=False
    )
    assert "[[e:" not in (out or "")
    assert "✦" in (out or "")


def test_editor_or_preview_tokens_keeps_when_allowed(db_session):
    owner = _user(db_session, 1)
    _activate(db_session, owner.id, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(owner.id, "Правка")
    item = emoji.add_emoji(
        user_id=owner.id,
        pack_id=pack.id,
        media_url="https://cdn.test/edit.webp",
    )
    db_session.commit()
    token = f"имя [[e:{item.id}]]"
    assert editor_or_preview_tokens(emoji, owner.id, token, own=True) == token


def test_update_group_title_admin_previews_creator_tokens(db_session):
    creator = _user(db_session, 1)
    admin = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, creator.id)
    _activate(db_session, admin.id, 10)
    conv = Conversation(
        type="group",
        title="Еда",
        created_by_user_id=creator.id,
    )
    db_session.add(conv)
    db_session.flush()
    db_session.add(
        ConversationMember(
            conversation_id=conv.id,
            user_id=creator.id,
            is_admin=True,
            can_change_info=True,
        )
    )
    db_session.add(
        ConversationMember(
            conversation_id=conv.id,
            user_id=admin.id,
            is_admin=True,
            can_change_info=True,
        )
    )
    db_session.commit()
    updated = ChatService(db_session).update_group_title(conv.id, admin.id, token)
    assert "[[e:" not in (updated.title or "")
    assert "✦" in (updated.title or "")
    with pytest.raises(ValueError, match="custom_emoji"):
        ChatService(db_session).update_group_title(conv.id, creator.id, token)


def test_update_forum_topic_admin_previews_author_tokens(db_session):
    creator = _user(db_session, 1)
    admin = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, creator.id)
    _activate(db_session, admin.id, 10)
    conv = Conversation(
        type="group",
        title="Форум",
        created_by_user_id=creator.id,
        is_forum=True,
    )
    db_session.add(conv)
    db_session.flush()
    db_session.add(
        ConversationMember(
            conversation_id=conv.id,
            user_id=creator.id,
            is_admin=True,
            can_change_info=True,
        )
    )
    db_session.add(
        ConversationMember(
            conversation_id=conv.id,
            user_id=admin.id,
            is_admin=True,
            can_change_info=True,
        )
    )
    topic = ForumTopic(
        conversation_id=conv.id,
        title="Новости",
        icon_emoji="📰",
        created_by_user_id=creator.id,
        is_general=False,
    )
    db_session.add(topic)
    db_session.commit()
    renamed = ChatService(db_session).update_forum_topic(
        conv.id, admin.id, topic.id, title=token, icon_emoji=token
    )
    assert "[[e:" not in (renamed.title or "")
    assert "✦" in (renamed.title or "")
    assert "[[e:" not in (renamed.icon_emoji or "")
    assert "✦" in (renamed.icon_emoji or "")
    with pytest.raises(ValueError, match="custom_emoji"):
        ChatService(db_session).update_forum_topic(
            conv.id, creator.id, topic.id, title=token
        )


def test_saved_tag_emoji_requires_custom_emoji(db_session):
    import asyncio

    from app.api.v1.chats import create_saved_tag
    from app.schemas.chat import SavedTagCreateRequest

    owner = _user(db_session, 1)
    _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await create_saved_tag(
            SavedTagCreateRequest(title="Работа", emoji="[[e:1]]"),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    assert err.value.status_code == 403


def test_quick_reply_service_requires_custom_emoji(db_session):
    from app.services.quick_reply_service import create_reply

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji"):
        create_reply(db_session, owner.id, "hi", token)


def test_quick_reply_share_subject_does_not_403_without_flex(db_session):
    from app.services.quick_reply_service import create_reply

    author = _user(db_session, 1)
    owner = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, author.id)
    row = create_reply(
        db_session,
        owner.id,
        "",
        f"Пост {token}\n\nОткрыть в HanWe: https://haneat.app/post/7",
    )
    db_session.commit()
    assert "[[e:" not in (row.text or "")
    assert "✦" in (row.text or "")
    assert "https://haneat.app/post/7" in (row.text or "")


def test_quick_reply_private_reply_header_does_not_403_without_flex(db_session):
    from app.services.quick_reply_service import create_reply

    author = _user(db_session, 1)
    owner = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, author.id)
    row = create_reply(
        db_session,
        owner.id,
        "цитата",
        f"↩️ {token}: {token}\n\nОк",
    )
    db_session.commit()
    assert "[[e:" not in (row.text or "")
    assert "Ок" in (row.text or "")


def test_quick_reply_share_body_tokens_still_require_flex(db_session):
    from app.services.quick_reply_service import create_reply

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji_required"):
        create_reply(
            db_session,
            owner.id,
            "",
            f"Пост\n\nОткрыть в HanWe: https://haneat.app/post/7\n{token}",
        )


def test_http_quick_reply_skips_token_gate_for_share_subject(db_session):
    import asyncio

    from app.api.v1.chats import create_quick_reply

    author = _user(db_session, 1)
    owner = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, author.id)
    _activate(db_session, owner.id, 60)

    async def _run():
        return await create_quick_reply(
            {
                "title": "",
                "text": f"Пост {token}\n\nОткрыть в HanWe: https://haneat.app/post/7",
            },
            current_user=owner,
            db=db_session,
        )

    created = asyncio.run(_run())
    assert "[[e:" not in (created["text"] or "")
    assert "✦" in (created["text"] or "")


def test_chat_tag_service_requires_custom_emoji(db_session):
    from app.services.chat_tag_service import create_tag

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji"):
        create_tag(db_session, owner.id, token)


def test_saved_tag_service_requires_custom_emoji(db_session):
    from app.services.saved_tag_service import create_tag

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji"):
        create_tag(db_session, owner.id, token)


def test_share_preview_hides_custom_emoji_tokens():
    out = preview_text_with_custom_emoji("Привет [[e:12]]")
    assert "[[e:" not in out
    assert "✦" in out


def test_miniapp_init_user_previews_custom_emoji():
    from types import SimpleNamespace

    from app.api.v1.miniapps import _serialize_user

    user = SimpleNamespace(id=1, name="Анна [[e:12]]", username="anna")
    out = _serialize_user(user)
    assert "[[e:" not in out["first_name"]
    assert "✦" in out["first_name"]


def test_checklist_title_requires_custom_emoji(db_session):
    import asyncio

    from fastapi import BackgroundTasks

    from app.api.v1.chats import send_message
    from app.schemas.chat import SendMessageRequest

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await send_message(
            1,
            SendMessageRequest(
                type="checklist",
                checklist_title=token,
                checklist_items=["хлеб"],
            ),
            BackgroundTasks(),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    assert err.value.status_code == 403


def test_admin_flex_feature_title_requires_custom_emoji(db_session):
    from app.api.v1.flex_subscription import admin_create_feature
    from app.schemas.flex_subscription import FlexFeatureWrite

    admin = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, admin.id)
    with pytest.raises(HTTPException) as err:
        admin_create_feature(
            FlexFeatureWrite(slug="tokfeat", title=token),
            admin,
            db_session,
        )
    assert err.value.status_code == 403


def test_admin_flex_block_title_requires_custom_emoji(db_session):
    from app.api.v1.flex_subscription import admin_upsert_block
    from app.schemas.flex_subscription import FlexBlockWrite

    admin = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, admin.id)
    with pytest.raises(HTTPException) as err:
        admin_upsert_block(
            FlexBlockWrite(key="tokblock", title=token),
            admin,
            db_session,
        )
    assert err.value.status_code == 403


def test_gif_favorite_title_requires_custom_emoji(db_session):
    from app.services.gif_favorite_service import toggle_favorite

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(HTTPException) as err:
        toggle_favorite(
            db_session,
            owner.id,
            "https://cdn.test/g.gif",
            title=token,
        )
    assert err.value.status_code == 403


def test_star_gift_note_requires_custom_emoji(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(HTTPException) as err:
        PaidFeaturesService(db_session).send_star_gift(
            owner.id,
            gift_id=1,
            conversation_id=1,
            message=token,
        )
    assert err.value.status_code == 403


def test_moderation_text_previews_custom_emoji():
    assert text_for_moderation("") == ""
    assert text_for_moderation("   ") == ""
    out = text_for_moderation("привет [[e:12]]")
    assert "[[e:" not in out
    assert "✦" in out
    long_body = ("слово " * 40) + "[[e:12]] хвост"
    long_out = text_for_moderation(long_body)
    assert "хвост" in long_out
    assert "[[e:" not in long_out
    assert text_for_translation("имя [[e:9]]") == "имя ✦"


def test_story_reaction_emoji_fits_ce_token():
    from app.models.story import StoryReaction

    assert StoryReaction.__table__.c.emoji.type.length >= 32


def _assert_custom_emoji_feature(exc: HTTPException) -> None:
    assert exc.status_code == 403
    detail = exc.detail
    assert isinstance(detail, dict)
    assert detail.get("feature") == "custom_emoji"


def test_business_greeting_tokens_before_flex(db_session):
    from app.services.business_profile_service import update_settings

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(HTTPException) as err:
        update_settings(
            db_session,
            owner,
            {"greeting_enabled": True, "greeting_text": token},
        )
    _assert_custom_emoji_feature(err.value)


def test_business_away_tokens_before_flex(db_session):
    from app.services.business_profile_service import update_settings

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(HTTPException) as err:
        update_settings(
            db_session,
            owner,
            {"away_enabled": True, "away_text": token, "away_mode": "manual"},
        )
    _assert_custom_emoji_feature(err.value)


def test_business_intro_tokens_before_flex(db_session):
    from app.services.business_profile_service import update_settings

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(HTTPException) as err:
        update_settings(
            db_session,
            owner,
            {"intro_title": token, "intro_text": "о нас"},
        )
    _assert_custom_emoji_feature(err.value)


def test_story_caption_tokens_before_close_friends(db_session):
    import asyncio

    from app.api.v1.stories import StoryCreateRequest, create_story

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await create_story(
            StoryCreateRequest(
                media_url="https://cdn.test/s.jpg",
                media_type="image",
                caption=token,
                visibility="close_friends",
            ),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    _assert_custom_emoji_feature(err.value)


def test_schedule_tokens_before_scheduled_flex(db_session):
    import asyncio
    from datetime import datetime, timedelta, timezone

    from app.api.v1.chats import schedule_message
    from app.schemas.chat import ScheduleMessageRequest

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await schedule_message(
            1,
            ScheduleMessageRequest(
                content=token,
                send_at=datetime.now(timezone.utc) + timedelta(hours=1),
            ),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    _assert_custom_emoji_feature(err.value)


def test_emoji_pack_create_tokens_before_publish_flex(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji_required"):
        EmojiPackService(db_session).create_pack(owner.id, token)


def test_poll_option_tokens_before_message_query(db_session):
    from app.services.chat_poll_service import add_option_to_message_poll

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji_required"):
        add_option_to_message_poll(db_session, 999, owner.id, token)


def test_add_sticker_tokens_before_animated_flex(db_session):
    import asyncio

    from app.api.v1.stickers import add_sticker_to_pack
    from app.schemas.sticker import AddStickerRequest

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await add_sticker_to_pack(
            1,
            AddStickerRequest(
                media_url="https://cdn.test/s.webp",
                emoji=token,
                sticker_type="animated",
            ),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    _assert_custom_emoji_feature(err.value)


def test_add_emoji_shortcode_returns_flex_gate(db_session):
    from app.api.v1.emoji_packs import AddEmojiIn, add_custom_emoji

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(HTTPException) as err:
        add_custom_emoji(
            1,
            AddEmojiIn(media_url="https://cdn.test/e.webp", shortcode=token),
            current_user=owner,
            db=db_session,
        )
    _assert_custom_emoji_feature(err.value)


def test_folder_and_saved_tag_schema_accepts_token():
    from app.schemas.chat import CreateChatFolderRequest, SavedTagCreateRequest

    token = "имя [[e:123]]"
    assert CreateChatFolderRequest(name="Работа", icon=token).icon == token
    assert SavedTagCreateRequest(title="Работа", emoji=token).emoji == token


def test_draft_upsert_returns_flex_gate(db_session):
    import asyncio

    from app.api.v1.chats import upsert_chat_draft
    from app.schemas.chat import ConversationDraftRequest

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await upsert_chat_draft(
            1,
            ConversationDraftRequest(text=token),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    _assert_custom_emoji_feature(err.value)


def test_folder_icon_keeps_custom_emoji_token(db_session):
    owner = _user(db_session, 1)
    _activate(db_session, owner.id, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(owner.id, "Папка")
    item = emoji.add_emoji(
        user_id=owner.id,
        pack_id=pack.id,
        media_url="https://cdn.test/folder.webp",
    )
    db_session.commit()
    token = f"имя [[e:{item.id}]]"
    row = ChatService(db_session).create_folder(owner.id, "Работа", token)
    db_session.commit()
    assert row["icon"] == token
    assert len(token) > 8


def test_saved_tag_emoji_keeps_custom_emoji_token(db_session):
    from app.services.saved_tag_service import create_tag

    owner = _user(db_session, 1)
    _activate(db_session, owner.id, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(owner.id, "Тег")
    item = emoji.add_emoji(
        user_id=owner.id,
        pack_id=pack.id,
        media_url="https://cdn.test/tag.webp",
    )
    db_session.commit()
    token = f"имя [[e:{item.id}]]"
    tag = create_tag(db_session, owner.id, "Работа", token)
    db_session.commit()
    assert tag.emoji == token
    assert len(token) > 8


def test_forward_blank_sender_name_is_not_soobshenie(db_session):
    sender = User(
        id=3, email="blank@t.test", password_hash="h", name="   ", username=None
    )
    forwarder = _user(db_session, 2)
    db_session.add(sender)
    db_session.commit()
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add(
        ConversationMember(conversation_id=conv.id, user_id=sender.id)
    )
    db_session.add(
        ConversationMember(conversation_id=conv.id, user_id=forwarder.id)
    )
    src = Message(
        conversation_id=conv.id,
        sender_id=sender.id,
        type="text",
        content="привет",
    )
    db_session.add(src)
    db_session.commit()
    out = ChatService(db_session).forward_message(
        target_conversation_id=conv.id,
        source_conversation_id=conv.id,
        message_id=src.id,
        sender_id=forwarder.id,
    )
    assert out.forward_from_name != "Сообщение"
    assert (out.forward_from_name or "").strip()


def test_forward_empty_forward_name_is_not_soobshenie(db_session):
    owner = _user(db_session, 1)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add(ConversationMember(conversation_id=conv.id, user_id=owner.id))
    src = Message(
        conversation_id=conv.id,
        sender_id=owner.id,
        type="text",
        content="привет",
        forward_from_user_id=9,
        forward_from_name="",
    )
    db_session.add(src)
    db_session.commit()
    out = ChatService(db_session).forward_message(
        target_conversation_id=conv.id,
        source_conversation_id=conv.id,
        message_id=src.id,
        sender_id=owner.id,
    )
    assert out.forward_from_name != "Сообщение"


def test_forward_tokens_return_flex_gate(db_session):
    import asyncio

    from fastapi import BackgroundTasks

    from app.api.v1.chats import forward_message
    from app.schemas.chat import ForwardMessageRequest

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add(ConversationMember(conversation_id=conv.id, user_id=owner.id))
    msg = Message(
        conversation_id=conv.id,
        sender_id=owner.id,
        type="text",
        content=token,
    )
    db_session.add(msg)
    db_session.commit()

    async def _run():
        await forward_message(
            conv.id,
            ForwardMessageRequest(
                source_conversation_id=conv.id,
                message_id=msg.id,
            ),
            BackgroundTasks(),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    _assert_custom_emoji_feature(err.value)


def test_prepare_forward_content_previews_peer_tokens(db_session):
    author = _user(db_session, 1)
    forwarder = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, author.id)
    emoji = EmojiPackService(db_session)
    assert prepare_forward_content(
        emoji, author.id, token, original_author_id=author.id
    ) == token
    previewed = prepare_forward_content(
        emoji, forwarder.id, token, original_author_id=author.id
    )
    assert previewed != token
    assert "[[e:" not in (previewed or "")


def test_forward_peer_tokens_does_not_403(db_session):
    author = _user(db_session, 1)
    forwarder = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, author.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add_all(
        [
            ConversationMember(conversation_id=conv.id, user_id=author.id),
            ConversationMember(conversation_id=conv.id, user_id=forwarder.id),
        ]
    )
    src = Message(
        conversation_id=conv.id,
        sender_id=author.id,
        type="text",
        content=token,
    )
    db_session.add(src)
    db_session.commit()
    out = ChatService(db_session).forward_message(
        target_conversation_id=conv.id,
        source_conversation_id=conv.id,
        message_id=src.id,
        sender_id=forwarder.id,
    )
    db_session.commit()
    assert out.sender_id == forwarder.id
    assert "[[e:" not in (out.content or "")
    assert (out.content or "").strip()


def test_reply_keyboard_tap_does_not_403_without_flex(db_session):
    import json

    owner = _user(db_session, 1)
    sender = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    member = ConversationMember(conversation_id=conv.id, user_id=sender.id)
    member.reply_keyboard_json = json.dumps([[{"text": token}]], ensure_ascii=False)
    db_session.add_all(
        [
            ConversationMember(conversation_id=conv.id, user_id=owner.id),
            member,
        ]
    )
    db_session.commit()
    msg, _ = ChatService(db_session).send_message(
        conversation_id=conv.id,
        sender_id=sender.id,
        msg_type="text",
        content=token,
        notify=False,
    )
    db_session.commit()
    assert "[[e:" not in (msg.content or "")
    assert (msg.content or "").strip()


def test_reply_keyboard_unrelated_tokens_still_require_flex(db_session):
    sender = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, sender.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add(ConversationMember(conversation_id=conv.id, user_id=sender.id))
    db_session.commit()
    with pytest.raises(ValueError, match="custom_emoji_required"):
        ChatService(db_session).send_message(
            conversation_id=conv.id,
            sender_id=sender.id,
            msg_type="text",
            content=token,
            notify=False,
        )


def test_http_skips_token_gate_for_reply_keyboard_label(db_session):
    import json

    from app.api.v1.chats import _require_send_text_tokens
    from app.schemas.chat import SendMessageRequest

    owner = _user(db_session, 1)
    sender = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    conv = Conversation(type="direct")
    db_session.add(conv)
    db_session.flush()
    member = ConversationMember(conversation_id=conv.id, user_id=sender.id)
    member.reply_keyboard_json = json.dumps([[{"text": token}]], ensure_ascii=False)
    db_session.add(member)
    db_session.commit()
    _require_send_text_tokens(
        db_session,
        sender,
        SendMessageRequest(type="text", content=token),
        conv.id,
    )


def test_sticker_associated_emoji_does_not_block_sender(db_session):
    owner = _user(db_session, 1)
    sender = _user(db_session, 2)
    _activate(db_session, owner.id, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(owner.id, "Гейт")
    item = emoji.add_emoji(
        user_id=owner.id,
        pack_id=pack.id,
        media_url="https://cdn.test/gate.webp",
    )
    token = f"имя [[e:{item.id}]]"
    stickers = StickerService(db_session)
    sticker_pack = stickers.create_pack(owner.id, "Коты", True)
    sticker = stickers.add_sticker(
        user_id=owner.id,
        pack_id=sticker_pack.id,
        media_url="https://cdn.test/cat-send.webp",
        emoji=token,
    )
    db_session.commit()
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add_all(
        [
            ConversationMember(conversation_id=conv.id, user_id=owner.id),
            ConversationMember(conversation_id=conv.id, user_id=sender.id),
        ]
    )
    db_session.commit()
    msg, _ = ChatService(db_session).send_message(
        conversation_id=conv.id,
        sender_id=sender.id,
        msg_type="sticker",
        content=token,
        media_url=sticker.media_url,
        notify=False,
    )
    db_session.commit()
    assert "[[e:" not in (msg.content or "")
    assert (msg.content or "").strip()


def test_http_skips_token_gate_for_sticker_emoji(db_session):
    from app.api.v1.chats import _require_send_text_tokens
    from app.schemas.chat import SendMessageRequest

    sender = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, sender.id)
    _require_send_text_tokens(
        db_session,
        sender,
        SendMessageRequest(type="sticker", content=token),
    )


def test_private_reply_quote_does_not_403_without_flex(db_session):
    author = _user(db_session, 1)
    sender = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, author.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add_all(
        [
            ConversationMember(conversation_id=conv.id, user_id=author.id),
            ConversationMember(conversation_id=conv.id, user_id=sender.id),
        ]
    )
    db_session.commit()
    content = f"↩️ {token}: {token}\n\nОк"
    msg, _ = ChatService(db_session).send_message(
        conversation_id=conv.id,
        sender_id=sender.id,
        msg_type="text",
        content=content,
        notify=False,
    )
    db_session.commit()
    assert "[[e:" not in (msg.content or "")
    assert "✦" in (msg.content or "")
    assert (msg.content or "").endswith("Ок")


def test_private_reply_body_tokens_still_require_flex(db_session):
    sender = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, sender.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add(ConversationMember(conversation_id=conv.id, user_id=sender.id))
    db_session.commit()
    with pytest.raises(ValueError, match="custom_emoji_required"):
        ChatService(db_session).send_message(
            conversation_id=conv.id,
            sender_id=sender.id,
            msg_type="text",
            content=f"↩️ Anna: hi\n\n{token}",
            notify=False,
        )


def test_http_skips_token_gate_for_private_reply_header(db_session):
    from app.api.v1.chats import _require_send_text_tokens
    from app.schemas.chat import SendMessageRequest

    sender = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, sender.id)
    _require_send_text_tokens(
        db_session,
        sender,
        SendMessageRequest(
            type="text",
            content=f"↩️ {token}: {token}\n\nОк",
        ),
    )


def test_hanwe_share_subject_does_not_403_without_flex(db_session):
    author = _user(db_session, 1)
    sender = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, author.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add_all(
        [
            ConversationMember(conversation_id=conv.id, user_id=author.id),
            ConversationMember(conversation_id=conv.id, user_id=sender.id),
        ]
    )
    db_session.commit()
    content = f"Пост {token}\n\nОткрыть в HanWe: https://haneat.app/post/7"
    msg, _ = ChatService(db_session).send_message(
        conversation_id=conv.id,
        sender_id=sender.id,
        msg_type="text",
        content=content,
        notify=False,
    )
    db_session.commit()
    assert "[[e:" not in (msg.content or "")
    assert "✦" in (msg.content or "")
    assert "https://haneat.app/post/7" in (msg.content or "")
    assert (msg.content or "").startswith("Пост")


def test_hanwe_share_body_tokens_still_require_flex(db_session):
    sender = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, sender.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add(ConversationMember(conversation_id=conv.id, user_id=sender.id))
    db_session.commit()
    with pytest.raises(ValueError, match="custom_emoji_required"):
        ChatService(db_session).send_message(
            conversation_id=conv.id,
            sender_id=sender.id,
            msg_type="text",
            content=(
                f"Пост\n\nОткрыть в HanWe: https://haneat.app/post/7\n{token}"
            ),
            notify=False,
        )


def test_hanwe_share_requires_haneat_url(db_session):
    sender = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, sender.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add(ConversationMember(conversation_id=conv.id, user_id=sender.id))
    db_session.commit()
    with pytest.raises(ValueError, match="custom_emoji_required"):
        ChatService(db_session).send_message(
            conversation_id=conv.id,
            sender_id=sender.id,
            msg_type="text",
            content=(
                f"Пост {token}\n\nОткрыть в HanWe: https://evil.example/post/7"
            ),
            notify=False,
        )


def test_http_skips_token_gate_for_hanwe_share_subject(db_session):
    from app.api.v1.chats import _require_send_text_tokens
    from app.schemas.chat import SendMessageRequest

    sender = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, sender.id)
    _require_send_text_tokens(
        db_session,
        sender,
        SendMessageRequest(
            type="text",
            content=f"Пост {token}\n\nОткрыть в HanWe: https://haneat.app/post/7",
        ),
    )


def test_sticker_emoji_keeps_long_token(db_session):
    owner = _user(db_session, 1)
    _activate(db_session, owner.id, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(owner.id, "Стикер")
    item = emoji.add_emoji(
        user_id=owner.id,
        pack_id=pack.id,
        media_url="https://cdn.test/st.webp",
    )
    db_session.commit()
    token = f"associated [[e:{item.id}]]"
    stickers = StickerService(db_session)
    sticker_pack = stickers.create_pack(owner.id, "Коты", True)
    sticker = stickers.add_sticker(
        user_id=owner.id,
        pack_id=sticker_pack.id,
        media_url="https://cdn.test/cat.webp",
        emoji=token,
    )
    db_session.commit()
    assert sticker.emoji == token
    assert len(token) > 16


def test_authored_send_texts_skips_peer_names():
    import json

    payload = json.dumps(
        {"story_id": 1, "text": "круто", "author_name": "Имя [[e:9]]"},
        ensure_ascii=False,
    )
    assert authored_send_texts("story_reply", payload) == ["круто"]
    card = "👤 Контакт\nИмя [[e:9]]\n@peer"
    assert authored_send_texts("text", card) == []
    assert authored_send_texts("sticker", "👍 [[e:9]]") == []
    assert authored_send_texts("text", "привет [[e:9]]") == ["привет [[e:9]]"]
    assert authored_send_texts(
        "text", "↩️ Anna [[e:9]]: Hello [[e:9]]\n\nSure"
    ) == ["Sure"]
    assert authored_send_texts("text", "↩️ Anna [[e:9]]: Hello") == [""]
    share = "Пост [[e:9]]\n\nОткрыть в HanWe: https://haneat.app/post/1"
    assert authored_send_texts("text", share) == []
    assert authored_send_texts("text", f"{share}\nМой коммент [[e:9]]") == [
        "Мой коммент [[e:9]]"
    ]
    assert split_hanwe_share("просто текст") == (None, "просто текст")
    assert split_hanwe_share(share) == (
        "Пост [[e:9]]",
        "\n\nОткрыть в HanWe: https://haneat.app/post/1",
    )


def test_story_reply_author_name_does_not_block_sender(db_session):
    import json

    author = _user(db_session, 1)
    sender = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, author.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add_all(
        [
            ConversationMember(conversation_id=conv.id, user_id=author.id),
            ConversationMember(conversation_id=conv.id, user_id=sender.id),
        ]
    )
    db_session.commit()
    content = json.dumps(
        {"story_id": 7, "text": "круто", "author_id": author.id, "author_name": token},
        ensure_ascii=False,
    )
    msg, _ = ChatService(db_session).send_message(
        conversation_id=conv.id,
        sender_id=sender.id,
        msg_type="story_reply",
        content=content,
        notify=False,
    )
    db_session.commit()
    assert "[[e:" not in (msg.content or "")
    assert "круто" in (msg.content or "")


def test_story_reply_own_text_still_requires_flex(db_session):
    import json

    author = _user(db_session, 1)
    sender = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, sender.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add_all(
        [
            ConversationMember(conversation_id=conv.id, user_id=author.id),
            ConversationMember(conversation_id=conv.id, user_id=sender.id),
        ]
    )
    db_session.commit()
    content = json.dumps(
        {"story_id": 7, "text": token, "author_id": author.id, "author_name": "Анна"},
        ensure_ascii=False,
    )
    with pytest.raises(ValueError, match="custom_emoji_required"):
        ChatService(db_session).send_message(
            conversation_id=conv.id,
            sender_id=sender.id,
            msg_type="story_reply",
            content=content,
        )


def test_contact_card_name_does_not_block_sender(db_session):
    peer = _user(db_session, 1)
    sender = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, peer.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add_all(
        [
            ConversationMember(conversation_id=conv.id, user_id=peer.id),
            ConversationMember(conversation_id=conv.id, user_id=sender.id),
        ]
    )
    db_session.commit()
    card = f"👤 Контакт\n{token}\n@peer"
    msg, _ = ChatService(db_session).send_message(
        conversation_id=conv.id,
        sender_id=sender.id,
        msg_type="text",
        content=card,
        notify=False,
    )
    db_session.commit()
    assert "[[e:" not in (msg.content or "")
    assert "Контакт" in (msg.content or "")


def test_contact_card_keeps_long_peer_name_without_flex(db_session):
    peer = _user(db_session, 1)
    sender = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, peer.id)
    long_name = ("А" * 90) + f" {token}"
    card = (
        f"👤 Контакт\n{long_name}\n@peer_handle\n+79991234567\n"
        f"haneat_user:{peer.id}"
    )
    assert len(card) > 120
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add_all(
        [
            ConversationMember(conversation_id=conv.id, user_id=peer.id),
            ConversationMember(conversation_id=conv.id, user_id=sender.id),
        ]
    )
    db_session.commit()
    msg, _ = ChatService(db_session).send_message(
        conversation_id=conv.id,
        sender_id=sender.id,
        msg_type="text",
        content=card,
        notify=False,
    )
    db_session.commit()
    stored = msg.content or ""
    assert "[[e:" not in stored
    assert "✦" in stored
    assert "А" * 90 in stored
    assert "@peer_handle" in stored
    assert "+79991234567" in stored
    assert f"haneat_user:{peer.id}" in stored
    assert len(stored) > 120


def test_story_reply_keeps_long_author_name_without_flex(db_session):
    import json

    author = _user(db_session, 1)
    sender = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, author.id)
    long_name = ("Б" * 90) + f" {token}"
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add_all(
        [
            ConversationMember(conversation_id=conv.id, user_id=author.id),
            ConversationMember(conversation_id=conv.id, user_id=sender.id),
        ]
    )
    db_session.commit()
    content = json.dumps(
        {
            "story_id": 7,
            "text": "круто",
            "author_id": author.id,
            "author_name": long_name,
        },
        ensure_ascii=False,
    )
    msg, _ = ChatService(db_session).send_message(
        conversation_id=conv.id,
        sender_id=sender.id,
        msg_type="story_reply",
        content=content,
        notify=False,
    )
    db_session.commit()
    data = json.loads(msg.content or "{}")
    assert "[[e:" not in (data.get("author_name") or "")
    assert "✦" in (data.get("author_name") or "")
    assert "Б" * 90 in (data.get("author_name") or "")
    assert data.get("text") == "круто"


def test_import_shared_folder_previews_tokens_without_flex(db_session):
    owner = _user(db_session, 1)
    importer = _user(db_session, 2)
    _activate(db_session, owner.id, 70)
    _activate(db_session, importer.id, 57)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(owner.id, "Папка")
    item = emoji.add_emoji(
        user_id=owner.id,
        pack_id=pack.id,
        media_url="https://cdn.test/folder-share.webp",
    )
    db_session.commit()
    token = f"[[e:{item.id}]]"
    chats = ChatService(db_session)
    chats.create_folder(owner.id, f"Работа {token}", token)
    db_session.commit()
    shared = chats.share_folder(owner.id, chats.list_folders(owner.id)[0]["id"])
    db_session.commit()
    imported = chats.import_shared_folder(importer.id, shared["token"])
    db_session.commit()
    assert "[[e:" not in (imported["name"] or "")
    assert "[[e:" not in (imported.get("icon") or "")
    assert "Работа" in imported["name"]


def test_import_shared_folder_keeps_tokens_when_allowed(db_session):
    owner = _user(db_session, 1)
    importer = _user(db_session, 2)
    _activate(db_session, owner.id, 70)
    _activate(db_session, importer.id, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(owner.id, "Общая")
    item = emoji.add_emoji(
        user_id=owner.id,
        pack_id=pack.id,
        media_url="https://cdn.test/folder-keep.webp",
    )
    emoji.install_pack(importer.id, pack.id)
    db_session.commit()
    token = f"[[e:{item.id}]]"
    chats = ChatService(db_session)
    chats.create_folder(owner.id, f"Работа {token}", token)
    db_session.commit()
    shared = chats.share_folder(owner.id, chats.list_folders(owner.id)[0]["id"])
    db_session.commit()
    imported = chats.import_shared_folder(importer.id, shared["token"])
    db_session.commit()
    assert imported["name"] == f"Работа {token}"
    assert imported["icon"] == token


def test_update_imported_folder_does_not_403_after_downgrade(db_session):
    owner = _user(db_session, 1)
    importer = _user(db_session, 2)
    _activate(db_session, owner.id, 70)
    _activate(db_session, importer.id, 70)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(owner.id, "Общая")
    item = emoji.add_emoji(
        user_id=owner.id,
        pack_id=pack.id,
        media_url="https://cdn.test/folder-resave.webp",
    )
    emoji.install_pack(importer.id, pack.id)
    db_session.commit()
    token = f"[[e:{item.id}]]"
    chats = ChatService(db_session)
    chats.create_folder(owner.id, f"Работа {token}", token)
    db_session.commit()
    shared = chats.share_folder(owner.id, chats.list_folders(owner.id)[0]["id"])
    db_session.commit()
    imported = chats.import_shared_folder(importer.id, shared["token"])
    db_session.commit()
    _activate(db_session, importer.id, 57)
    updated = chats.update_folder(
        importer.id,
        imported["id"],
        name=imported["name"],
        icon=imported["icon"],
    )
    db_session.commit()
    assert updated is not None
    assert "[[e:" not in (updated["name"] or "")
    assert "Работа" in updated["name"]
    assert "[[e:" not in (updated.get("icon") or "")


def test_update_folder_new_tokens_still_require_flex(db_session):
    owner = _user(db_session, 1)
    chats = ChatService(db_session)
    folder = chats.create_folder(owner.id, "Папка")
    db_session.commit()
    token = _emoji_token_after_downgrade(db_session, owner.id)
    with pytest.raises(ValueError, match="custom_emoji_required"):
        chats.update_folder(owner.id, folder["id"], name=f"Новая {token}")


def test_reaction_and_topic_schema_accepts_token():
    from app.schemas.chat import (
        ForumTopicCreateRequest,
        MessageReactionRequest,
    )
    from app.schemas.sticker import AddStickerRequest

    token = "associated [[e:123]]"
    assert MessageReactionRequest(emoji=token).emoji == token
    assert ForumTopicCreateRequest(title="Тема", icon_emoji=token).icon_emoji == token
    assert AddStickerRequest(
        media_url="https://cdn.test/s.webp",
        emoji=token,
    ).emoji == token


def test_edit_contact_card_previews_peer_name_without_flex(db_session):
    peer = _user(db_session, 1)
    sender = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, peer.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add_all(
        [
            ConversationMember(conversation_id=conv.id, user_id=peer.id),
            ConversationMember(conversation_id=conv.id, user_id=sender.id),
        ]
    )
    msg = Message(
        conversation_id=conv.id,
        sender_id=sender.id,
        type="text",
        content=f"👤 Контакт\n{token}\n@peer",
    )
    db_session.add(msg)
    db_session.commit()
    edited = ChatService(db_session).edit_message(
        conv.id, msg.id, sender.id, f"👤 Контакт\n{token}\n@peer"
    )
    db_session.commit()
    assert "[[e:" not in (edited.content or "")
    assert "Контакт" in (edited.content or "")


def test_edit_own_text_still_requires_flex(db_session):
    sender = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, sender.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add(ConversationMember(conversation_id=conv.id, user_id=sender.id))
    msg = Message(
        conversation_id=conv.id,
        sender_id=sender.id,
        type="text",
        content="привет",
    )
    db_session.add(msg)
    db_session.commit()
    with pytest.raises(ValueError, match="custom_emoji_required"):
        ChatService(db_session).edit_message(conv.id, msg.id, sender.id, token)


def test_reschedule_contact_card_previews_peer_name_without_flex(db_session):
    from datetime import datetime, timedelta, timezone

    peer = _user(db_session, 1)
    sender = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, peer.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add_all(
        [
            ConversationMember(conversation_id=conv.id, user_id=peer.id),
            ConversationMember(conversation_id=conv.id, user_id=sender.id),
        ]
    )
    when = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(hours=2)
    item = ScheduledMessage(
        conversation_id=conv.id,
        sender_id=sender.id,
        type="text",
        content="позже",
        send_at=when,
        status="pending",
    )
    db_session.add(item)
    db_session.commit()
    updated = ChatService(db_session).reschedule_message(
        conversation_id=conv.id,
        scheduled_message_id=item.id,
        user_id=sender.id,
        content=f"👤 Контакт\n{token}\n@peer",
    )
    db_session.commit()
    assert "[[e:" not in (updated.content or "")
    assert "Контакт" in (updated.content or "")


def test_reschedule_image_share_subject_does_not_403_without_flex(db_session):
    from datetime import datetime, timedelta, timezone

    author = _user(db_session, 1)
    sender = _user(db_session, 2)
    token = _emoji_token_after_downgrade(db_session, author.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add_all(
        [
            ConversationMember(conversation_id=conv.id, user_id=author.id),
            ConversationMember(conversation_id=conv.id, user_id=sender.id),
        ]
    )
    when = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(hours=2)
    item = ScheduledMessage(
        conversation_id=conv.id,
        sender_id=sender.id,
        type="image",
        content="фото",
        send_at=when,
        status="pending",
    )
    db_session.add(item)
    db_session.commit()
    updated = ChatService(db_session).reschedule_message(
        conversation_id=conv.id,
        scheduled_message_id=item.id,
        user_id=sender.id,
        content=f"Пост {token}\n\nОткрыть в HanWe: https://haneat.app/post/7",
    )
    db_session.commit()
    assert "[[e:" not in (updated.content or "")
    assert "✦" in (updated.content or "")
    assert "https://haneat.app/post/7" in (updated.content or "")


def test_reschedule_image_caption_tokens_still_require_flex(db_session):
    from datetime import datetime, timedelta, timezone

    sender = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, sender.id)
    conv = Conversation(type="group", title="Чат")
    db_session.add(conv)
    db_session.flush()
    db_session.add(ConversationMember(conversation_id=conv.id, user_id=sender.id))
    when = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(hours=2)
    item = ScheduledMessage(
        conversation_id=conv.id,
        sender_id=sender.id,
        type="image",
        content="фото",
        send_at=when,
        status="pending",
    )
    db_session.add(item)
    db_session.commit()
    with pytest.raises(ValueError, match="custom_emoji_required"):
        ChatService(db_session).reschedule_message(
            conversation_id=conv.id,
            scheduled_message_id=item.id,
            user_id=sender.id,
            content=f"подпись {token}",
        )


def _group_chat(db, *users):
    conv = Conversation(type="group", title="Чат")
    db.add(conv)
    db.flush()
    db.add_all(
        [ConversationMember(conversation_id=conv.id, user_id=u.id) for u in users]
    )
    db.commit()
    return conv


def test_send_text_voice_video_note_and_photo_without_flex(db_session):
    sender = _user(db_session, 1)
    peer = _user(db_session, 2)
    conv = _group_chat(db_session, sender, peer)
    chat = ChatService(db_session)

    text, _ = chat.send_message(
        conversation_id=conv.id,
        sender_id=sender.id,
        msg_type="text",
        content="привет",
        notify=False,
    )
    voice, _ = chat.send_message(
        conversation_id=conv.id,
        sender_id=sender.id,
        msg_type="voice",
        content="12",
        media_url="https://cdn.test/voice.m4a",
        notify=False,
    )
    note, _ = chat.send_message(
        conversation_id=conv.id,
        sender_id=sender.id,
        msg_type="video_note",
        content="3",
        media_url="https://cdn.test/circle.mp4",
        notify=False,
    )
    photo, _ = chat.send_message(
        conversation_id=conv.id,
        sender_id=sender.id,
        msg_type="image",
        content="",
        media_url="https://cdn.test/photo.jpg",
        notify=False,
    )
    db_session.commit()
    assert text.content == "привет"
    assert voice.type == "voice"
    assert voice.media_url.endswith("voice.m4a")
    assert note.type == "video_note"
    assert note.media_url.endswith("circle.mp4")
    assert photo.type == "image"
    assert (photo.content or "") == ""


def test_http_send_voice_and_video_note_do_not_token_gate(db_session):
    from app.api.v1.chats import _require_send_flex_options, _require_send_text_tokens
    from app.schemas.chat import SendMessageRequest

    sender = _user(db_session, 1)
    voice = SendMessageRequest(
        type="voice",
        content="12",
        media_url="https://cdn.test/voice.m4a",
    )
    note = SendMessageRequest(
        type="video_note",
        content="3",
        media_url="https://cdn.test/circle.mp4",
    )
    photo = SendMessageRequest(
        type="image",
        content="",
        media_url="https://cdn.test/photo.jpg",
    )
    _require_send_text_tokens(db_session, sender, voice)
    _require_send_text_tokens(db_session, sender, note)
    _require_send_text_tokens(db_session, sender, photo)
    _require_send_flex_options(db_session, sender, voice)
    _require_send_flex_options(db_session, sender, photo)
    with pytest.raises(HTTPException) as err:
        _require_send_flex_options(db_session, sender, note)
    assert err.value.status_code == 403
    _activate(db_session, sender.id, 28)
    _require_send_flex_options(db_session, sender, note)


def test_http_send_voice_and_photo_persist(db_session):
    import asyncio

    from fastapi import BackgroundTasks

    from app.api.v1.chats import send_message
    from app.schemas.chat import SendMessageRequest

    sender = _user(db_session, 1)
    peer = _user(db_session, 2)
    conv = _group_chat(db_session, sender, peer)

    async def _run():
        voice = await send_message(
            conv.id,
            SendMessageRequest(
                type="voice",
                content="8",
                media_url="https://cdn.test/v.m4a",
            ),
            BackgroundTasks(),
            current_user=sender,
            db=db_session,
        )
        photo = await send_message(
            conv.id,
            SendMessageRequest(
                type="image",
                content="",
                media_url="https://cdn.test/p.jpg",
            ),
            BackgroundTasks(),
            current_user=sender,
            db=db_session,
        )
        return voice, photo

    voice, photo = asyncio.run(_run())
    assert voice.type == "voice"
    assert voice.media_url.endswith("v.m4a")
    assert photo.type == "image"


def test_http_send_video_note_with_flex_persists(db_session):
    import asyncio

    from fastapi import BackgroundTasks

    from app.api.v1.chats import send_message
    from app.schemas.chat import SendMessageRequest

    sender = _user(db_session, 1)
    peer = _user(db_session, 2)
    _activate(db_session, sender.id, 28)
    conv = _group_chat(db_session, sender, peer)

    async def _run():
        return await send_message(
            conv.id,
            SendMessageRequest(
                type="video_note",
                content="4",
                media_url="https://cdn.test/circle.mp4",
            ),
            BackgroundTasks(),
            current_user=sender,
            db=db_session,
        )

    note = asyncio.run(_run())
    assert note.type == "video_note"
    assert note.media_url.endswith("circle.mp4")


def test_create_story_without_caption_or_flex(db_session):
    import asyncio

    from app.api.v1.stories import StoryCreateRequest, create_story

    owner = _user(db_session, 1)

    async def _run():
        photo = await create_story(
            StoryCreateRequest(
                media_url="https://cdn.test/s.jpg",
                media_type="image",
            ),
            current_user=owner,
            db=db_session,
        )
        video = await create_story(
            StoryCreateRequest(
                media_url="https://cdn.test/s.mp4",
                media_type="video",
                caption=None,
            ),
            current_user=owner,
            db=db_session,
        )
        return photo, video

    photo, video = asyncio.run(_run())
    assert photo.media_type == "image"
    assert photo.caption is None
    assert video.media_type == "video"
    assert db_session.query(Story).count() == 2


def test_empty_post_fields_do_not_require_custom_emoji(db_session):
    from app.schemas.post import CreatePostRequest, MediaItem

    owner = _user(db_session, 1)
    photo = CreatePostRequest(
        type="photo",
        title=None,
        description=None,
        media=[MediaItem(type="image", url="https://cdn.test/p.jpg")],
    )
    text = CreatePostRequest(type="text", title="Новость", description="текст")
    reel = CreatePostRequest(
        type="reel",
        title=None,
        description=None,
        media=[MediaItem(type="video", url="https://cdn.test/r.mp4")],
    )
    emoji = EmojiPackService(db_session)
    emoji.require_send_tokens_http(
        owner.id,
        photo.title,
        photo.description,
        *(photo.tags or []),
    )
    emoji.require_send_tokens_http(
        owner.id,
        text.title,
        text.description,
        *(text.tags or []),
    )
    emoji.require_send_tokens_http(
        owner.id,
        reel.title,
        reel.description,
        *(reel.tags or []),
    )


def test_link_preview_og_title_does_not_403_without_flex(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    emoji = EmojiPackService(db_session)
    # Flutter echoes the OG title when the preview field is empty.
    out = link_preview_for_persist(
        emoji, owner.id, token, og_title=token
    )
    assert out is not None
    assert "[[e:" not in out
    assert "✦" in out


def test_link_preview_empty_falls_back_to_og_without_flex(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    emoji = EmojiPackService(db_session)
    out = link_preview_for_persist(emoji, owner.id, "", og_title=token)
    assert out is not None
    assert "[[e:" not in out


def test_link_preview_resave_stored_does_not_403(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    emoji = EmojiPackService(db_session)
    out = link_preview_for_persist(
        emoji, owner.id, token, stored=token, og_title="Example"
    )
    assert out is not None
    assert "[[e:" not in out


def test_link_preview_typed_tokens_still_require_flex(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    emoji = EmojiPackService(db_session)
    with pytest.raises(ValueError, match="custom_emoji_required"):
        link_preview_for_persist(
            emoji, owner.id, token, og_title="Example Domain"
        )


def test_http_link_preview_og_echo_does_not_403(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    emoji = EmojiPackService(db_session)
    out = link_preview_for_persist_http(
        emoji, owner.id, token, og_title=token
    )
    assert "[[e:" not in (out or "")


def test_http_link_preview_typed_tokens_return_flex_gate(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    emoji = EmojiPackService(db_session)
    with pytest.raises(HTTPException) as err:
        link_preview_for_persist_http(
            emoji, owner.id, token, og_title="Example Domain"
        )
    assert err.value.status_code == 403


def test_keep_if_unchanged_resave_does_not_403(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    emoji = EmojiPackService(db_session)
    out = keep_if_unchanged(emoji, owner.id, token, token)
    assert "[[e:" not in (out or "")
    assert "имя" in (out or "")
    http_out = keep_if_unchanged_http(emoji, owner.id, token, token)
    assert "[[e:" not in (http_out or "")


def test_keep_if_unchanged_new_tokens_still_require_flex(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    emoji = EmojiPackService(db_session)
    with pytest.raises(ValueError, match="custom_emoji_required"):
        keep_if_unchanged(emoji, owner.id, token, "Кухня")
    with pytest.raises(HTTPException) as err:
        keep_if_unchanged_http(emoji, owner.id, token, "Кухня")
    assert err.value.status_code == 403


def test_update_profile_resave_name_does_not_403(db_session):
    import asyncio

    from app.api.v1.users import update_user_profile
    from app.schemas.user import UpdateUserRequest

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    owner.name = token
    owner.bio = "старое"
    db_session.commit()

    async def _run():
        return await update_user_profile(
            request=UpdateUserRequest(name=token, bio="новое био"),
            current_user=owner,
            db=db_session,
        )

    updated = asyncio.run(_run())
    assert "[[e:" not in (updated.name or "")
    assert "имя" in (updated.name or "")
    assert updated.bio == "новое био"


def test_update_profile_new_name_tokens_still_require_flex(db_session):
    import asyncio

    from app.api.v1.users import update_user_profile
    from app.schemas.user import UpdateUserRequest

    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)

    async def _run():
        await update_user_profile(
            request=UpdateUserRequest(name=token),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_run())
    assert err.value.status_code == 403


def test_keep_if_unchanged_items_keeps_old_tags(db_session):
    owner = _user(db_session, 1)
    token = _emoji_token_after_downgrade(db_session, owner.id)
    emoji = EmojiPackService(db_session)
    out = keep_if_unchanged_items(
        emoji, owner.id, [token, "новости"], [token], http=True
    )
    assert out is not None
    assert "[[e:" not in (out[0] or "")
    assert out[1] == "новости"
    with pytest.raises(HTTPException) as err:
        keep_if_unchanged_items(
            emoji, owner.id, [f"новая {token}"], ["новости"], http=True
        )
    assert err.value.status_code == 403


def test_resave_send_restriction_reason_does_not_403(db_session):
    creator = _user(db_session, 1)
    admin = _user(db_session, 2)
    target = _user(db_session, 3)
    _activate(db_session, creator.id, 70)
    _activate(db_session, admin.id, 10)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(creator.id, "Гейт")
    item = emoji.add_emoji(
        user_id=creator.id,
        pack_id=pack.id,
        media_url="https://cdn.test/restrict.webp",
    )
    db_session.commit()
    token = f"флуд [[e:{item.id}]]"
    conv = Conversation(
        type="group",
        title="Чат",
        created_by_user_id=creator.id,
    )
    db_session.add(conv)
    db_session.flush()
    db_session.add(
        ConversationMember(
            conversation_id=conv.id,
            user_id=creator.id,
            is_admin=True,
            can_manage_members=True,
        )
    )
    db_session.add(
        ConversationMember(
            conversation_id=conv.id,
            user_id=admin.id,
            is_admin=True,
            can_manage_members=True,
        )
    )
    db_session.add(ConversationMember(conversation_id=conv.id, user_id=target.id))
    db_session.commit()
    chats = ChatService(db_session)
    chats.set_group_member_send_restriction(
        conv.id,
        creator.id,
        target.id,
        send_restricted=True,
        send_restricted_until=None,
        reason=token,
    )
    db_session.commit()
    # Flutter resends the stored reason when changing only the deadline.
    updated = chats.set_group_member_send_restriction(
        conv.id,
        admin.id,
        target.id,
        send_restricted=True,
        send_restricted_until=None,
        reason=token,
    )
    db_session.commit()
    assert "[[e:" not in (updated.send_restriction_reason or "")
    assert "флуд" in (updated.send_restriction_reason or "")


def test_new_send_restriction_tokens_still_require_flex(db_session):
    creator = _user(db_session, 1)
    admin = _user(db_session, 2)
    target = _user(db_session, 3)
    token = _emoji_token_after_downgrade(db_session, admin.id)
    conv = Conversation(
        type="group",
        title="Чат",
        created_by_user_id=creator.id,
    )
    db_session.add(conv)
    db_session.flush()
    db_session.add(
        ConversationMember(
            conversation_id=conv.id,
            user_id=creator.id,
            is_admin=True,
            can_manage_members=True,
        )
    )
    db_session.add(
        ConversationMember(
            conversation_id=conv.id,
            user_id=admin.id,
            is_admin=True,
            can_manage_members=True,
        )
    )
    db_session.add(ConversationMember(conversation_id=conv.id, user_id=target.id))
    db_session.commit()
    with pytest.raises(ValueError, match="custom_emoji_required"):
        ChatService(db_session).set_group_member_send_restriction(
            conv.id,
            admin.id,
            target.id,
            send_restricted=True,
            send_restricted_until=None,
            reason=token,
        )


def _token_while_flex(db, user_id: int) -> str:
    _activate(db, user_id, 70)
    emoji = EmojiPackService(db)
    pack = emoji.create_pack(user_id, "Пак")
    item = emoji.add_emoji(
        user_id=user_id,
        pack_id=pack.id,
        media_url="https://cdn.test/resave.webp",
    )
    db.commit()
    return f"имя [[e:{item.id}]]"


def test_emoji_pack_resave_title_does_not_403(db_session):
    owner = _user(db_session, 1)
    token = _token_while_flex(db_session, owner.id)
    emoji = EmojiPackService(db_session)
    pack = emoji.create_pack(owner.id, token)
    db_session.commit()
    _activate(db_session, 1, 10)
    updated = emoji.update_pack(
        user_id=owner.id, pack_id=pack.id, title=token, is_public=False
    )
    assert updated.is_public is False
    assert "[[e:" not in updated.title
    assert "имя" in updated.title
    with pytest.raises(ValueError, match="custom_emoji_required"):
        emoji.update_pack(
            user_id=owner.id,
            pack_id=pack.id,
            title=f"новое {token}",
        )


def test_sticker_pack_resave_title_does_not_403(db_session):
    owner = _user(db_session, 1)
    token = _token_while_flex(db_session, owner.id)
    stickers = StickerService(db_session)
    pack = stickers.create_pack(owner.id, token, True)
    db_session.commit()
    _activate(db_session, 1, 10)
    updated = stickers.update_pack(
        user_id=owner.id, pack_id=pack.id, title=token, is_public=False
    )
    assert updated.is_public is False
    assert "[[e:" not in updated.title
    assert "имя" in updated.title
    with pytest.raises(ValueError, match="custom_emoji_required"):
        stickers.update_pack(
            user_id=owner.id,
            pack_id=pack.id,
            title=f"новое {token}",
        )


def test_business_greeting_resave_does_not_403(db_session):
    from app.services.business_profile_service import update_settings

    owner = _user(db_session, 1)
    token = _token_while_flex(db_session, owner.id)
    update_settings(
        db_session,
        owner,
        {"greeting_enabled": True, "greeting_text": token},
    )
    db_session.commit()
    _activate(db_session, 1, 68)
    update_settings(
        db_session,
        owner,
        {
            "greeting_enabled": False,
            "greeting_text": token,
            "greeting_inactivity_days": 14,
        },
    )
    row = (
        db_session.query(UserBusinessSettings)
        .filter(UserBusinessSettings.user_id == owner.id)
        .first()
    )
    assert row is not None
    assert row.greeting_enabled is False
    assert "[[e:" not in (row.greeting_text or "")
    assert "имя" in (row.greeting_text or "")
    with pytest.raises(HTTPException) as err:
        update_settings(
            db_session,
            owner,
            {"greeting_enabled": True, "greeting_text": f"новое {token}"},
        )
    assert err.value.status_code == 403


def test_business_away_resave_does_not_403(db_session):
    from app.services.business_profile_service import update_settings

    owner = _user(db_session, 1)
    token = _token_while_flex(db_session, owner.id)
    update_settings(
        db_session,
        owner,
        {"away_enabled": True, "away_text": token, "away_mode": "manual"},
    )
    db_session.commit()
    _activate(db_session, 1, 68)
    update_settings(
        db_session,
        owner,
        {"away_enabled": False, "away_text": token, "away_mode": "outside_hours"},
    )
    row = (
        db_session.query(UserBusinessSettings)
        .filter(UserBusinessSettings.user_id == owner.id)
        .first()
    )
    assert row is not None
    assert "[[e:" not in (row.away_text or "")
    with pytest.raises(HTTPException) as err:
        update_settings(
            db_session,
            owner,
            {"away_enabled": True, "away_text": f"новое {token}", "away_mode": "manual"},
        )
    assert err.value.status_code == 403


def test_update_bot_resave_name_does_not_403(db_session):
    import asyncio

    from app.api.v1.bots import BotUpdateRequest, update_bot

    owner = _user(db_session, 1)
    token = _token_while_flex(db_session, owner.id)
    bot = User(
        id=10,
        email="bot@t.test",
        password_hash="h",
        name=token,
        is_bot=True,
        bot_username="cookbot",
        bot_token="tok-resave",
        created_by_user_id=owner.id,
        bot_description="старое",
    )
    db_session.add(bot)
    db_session.commit()
    _activate(db_session, 1, 10)

    async def _run():
        return await update_bot(
            bot_id=10,
            payload=BotUpdateRequest(name=token, description="новое"),
            current_user=owner,
            db=db_session,
        )

    result = asyncio.run(_run())
    assert "[[e:" not in result.name
    assert "имя" in result.name
    assert result.description == "новое"

    async def _new():
        return await update_bot(
            bot_id=10,
            payload=BotUpdateRequest(name=f"новое {token}"),
            current_user=owner,
            db=db_session,
        )

    with pytest.raises(HTTPException) as err:
        asyncio.run(_new())
    assert err.value.status_code == 403


def test_clip_preserving_custom_emoji_does_not_split_token():
    token = "[[e:123]]"
    prefix = "п" * 58
    raw = prefix + token
    assert len(raw) > 64
    clipped = clip_preserving_custom_emoji(raw, 64)
    assert "[[e:" not in clipped
    assert clipped == prefix
    assert clip_preserving_custom_emoji("короткое " + token, 64) == "короткое " + token
    assert clip_preserving_custom_emoji("abcdef", 3) == "abc"


def _bare_ce_token(token: str) -> str:
    return "[[e:" + token.split("[[e:", 1)[1]


def test_folder_create_does_not_persist_split_token(db_session):
    owner = _user(db_session, 1)
    token = _token_while_flex(db_session, owner.id)
    bare = _bare_ce_token(token)
    long_name = ("п" * 58) + bare
    row = ChatService(db_session).create_folder(owner.id, long_name)
    assert "[[e:" not in row["name"]
    assert row["name"] == "п" * 58


def test_quick_reply_does_not_persist_split_token(db_session):
    from app.services.quick_reply_service import create_reply

    owner = _user(db_session, 1)
    token = _token_while_flex(db_session, owner.id)
    bare = _bare_ce_token(token)
    long_title = ("п" * 34) + bare
    long_text = ("т" * 394) + bare
    row = create_reply(db_session, owner.id, long_title, long_text)
    assert "[[e:" not in row.title
    assert row.title == "п" * 34
    assert "[[e:" not in row.text
    assert row.text == "т" * 394


def test_quick_reply_auto_title_does_not_persist_split_token(db_session):
    from app.services.quick_reply_service import create_reply

    owner = _user(db_session, 1)
    token = _token_while_flex(db_session, owner.id)
    bare = _bare_ce_token(token)
    row = create_reply(db_session, owner.id, "", ("п" * 34) + bare)
    assert "[[e:" not in row.title
    assert row.title == "п" * 34


def test_saved_tag_does_not_persist_split_token(db_session):
    from app.services.saved_tag_service import create_tag

    owner = _user(db_session, 1)
    token = _token_while_flex(db_session, owner.id)
    bare = _bare_ce_token(token)
    tag = create_tag(db_session, owner.id, ("п" * 34) + bare, ("и" * 26) + bare)
    assert "[[e:" not in tag.title
    assert tag.title == "п" * 34
    assert "[[e:" not in (tag.emoji or "")
    assert tag.emoji == "и" * 26


def test_checklist_does_not_persist_split_token():
    from app.services.chat_checklist_service import (
        build_checklist_content,
        parse_checklist,
    )

    token = "[[e:12]]"
    raw = build_checklist_content(("п" * 194) + token, [("т" * 114) + token])
    parsed = parse_checklist(raw)
    assert parsed is not None
    assert "[[e:" not in parsed["title"]
    assert parsed["title"] == "п" * 194
    assert "[[e:" not in parsed["items"][0]["text"]
    assert parsed["items"][0]["text"] == "т" * 114


def test_admin_flex_feature_resave_title_does_not_403(db_session):
    from app.api.v1.flex_subscription import admin_update_feature
    from app.models.flex_subscription import SubscriptionFeature
    from app.schemas.flex_subscription import FlexFeatureWrite

    admin = _user(db_session, 1)
    token = _token_while_flex(db_session, admin.id)
    FlexSubscriptionService(db_session).ensure_catalog()
    feat = db_session.query(SubscriptionFeature).first()
    assert feat is not None
    feat.title = token
    feat.description = "старое"
    db_session.commit()
    _activate(db_session, 1, 10)
    out = admin_update_feature(
        feat.id,
        FlexFeatureWrite(title=token, description="новое", movable=False),
        admin,
        db_session,
    )
    assert "[[e:" not in (out["title"] or "")
    assert "имя" in out["title"]
    assert out["description"] == "новое"
    with pytest.raises(HTTPException) as err:
        admin_update_feature(
            feat.id,
            FlexFeatureWrite(title=f"новое {token}"),
            admin,
            db_session,
        )
    assert err.value.status_code == 403
