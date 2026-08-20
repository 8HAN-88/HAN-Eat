import os
from datetime import datetime, timedelta

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.models.flex_subscription import (
    SubscriptionFeature,
    SubscriptionFeatureBlock,
    UserFlexGift,
    UserFlexSlot,
    UserFlexSubscription,
)
from app.models.notification import Notification
from app.models.subscription import Subscription
from app.models.user import User
from app.services.flex_subscription_service import (
    FlexMoveError,
    FlexSubscriptionService,
    price_for_level,
    price_for_plan,
)
from app.services.subscription_service import SubscriptionService


@pytest.fixture()
def db_session():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    tables = [
        User.__table__,
        Subscription.__table__,
        SubscriptionFeatureBlock.__table__,
        SubscriptionFeature.__table__,
        UserFlexSubscription.__table__,
        UserFlexSlot.__table__,
        UserFlexGift.__table__,
        Notification.__table__,
    ]
    from app.core.database import Base

    Base.metadata.create_all(bind=engine, tables=tables)
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def _user(db, user_id: int = 1) -> User:
    u = User(
        id=user_id,
        email=f"u{user_id}@t.test",
        password_hash="h",
        name=f"U{user_id}",
    )
    db.add(u)
    db.commit()
    return u


def test_price_formula():
    assert price_for_level(1) == 39
    assert price_for_level(4) == 69
    assert price_for_level(5) == 79
    assert price_for_level(10) == 129
    assert price_for_level(16) == 189
    assert price_for_level(20) == 229
    assert price_for_level(24) == 269
    assert price_for_level(28) == 309
    assert price_for_level(32) == 349
    assert price_for_level(36) == 389
    assert price_for_level(40) == 429
    assert price_for_level(44) == 469
    assert price_for_level(48) == 509
    assert price_for_level(52) == 549
    assert price_for_level(56) == 589
    assert price_for_level(60) == 629
    assert price_for_plan(1, "yearly") == 390
    assert price_for_plan(6, "yearly") == 890
    assert price_for_plan(10, "yearly") == 1290
    assert price_for_plan(16, "yearly") == 1890
    assert price_for_plan(20, "yearly") == 2290
    assert price_for_plan(24, "yearly") == 2690
    assert price_for_plan(28, "yearly") == 3090
    assert price_for_plan(32, "yearly") == 3490
    assert price_for_plan(36, "yearly") == 3890
    assert price_for_plan(40, "yearly") == 4290
    assert price_for_plan(44, "yearly") == 4690
    assert price_for_plan(48, "yearly") == 5090
    assert price_for_plan(52, "yearly") == 5490
    assert price_for_plan(56, "yearly") == 5890
    assert price_for_plan(60, "yearly") == 6290


def test_catalog_seed_and_default_layout(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    layout = svc.resolved_layout(1)
    assert len(layout) == 60
    assert layout[0]["feature"].slug == "ad_free"
    assert layout[0]["level"] == 1
    assert layout[9]["feature"].slug == "priority_support"
    assert layout[9]["level"] == 10
    assert layout[15]["feature"].slug == "message_effects"
    assert layout[15]["level"] == 16
    assert layout[19]["feature"].slug == "story_close_friends"
    assert layout[19]["level"] == 20
    assert layout[23]["feature"].slug == "live_location"
    assert layout[23]["level"] == 24
    assert layout[27]["feature"].slug == "video_notes"
    assert layout[27]["level"] == 28
    assert layout[31]["feature"].slug == "folder_icons"
    assert layout[31]["level"] == 32
    assert layout[35]["feature"].slug == "profile_colors"
    assert layout[35]["level"] == 36
    assert layout[39]["feature"].slug == "archive_non_contacts"
    assert layout[39]["level"] == 40
    assert layout[43]["feature"].slug == "call_privacy"
    assert layout[43]["level"] == 44
    assert layout[51]["feature"].slug == "edit_history"
    assert layout[51]["level"] == 52
    assert layout[-1]["feature"].slug == "quick_replies"
    assert layout[-1]["level"] == 60


def test_cannot_move_fixed_feature(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    ad_free = next(f for f in svc.list_features() if f.slug == "ad_free")
    with pytest.raises(HTTPException) as exc:
        svc.move_feature(1, ad_free.id, 3)
    assert exc.value.status_code == 400


def test_move_within_block_and_reject_outside(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    reactions = next(f for f in svc.list_features() if f.slug == "exclusive_reactions")
    svc.move_feature(1, reactions.id, 3)
    db_session.commit()
    level = svc.feature_level(1, reactions)
    assert level == 3
    with pytest.raises(FlexMoveError):
        svc.move_feature(1, reactions.id, 5)


def test_activate_unlocks_assigned_levels(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    svc.activate(1, 4)
    db_session.commit()
    slugs = svc.unlocked_slugs(1)
    assert "ad_free" in slugs
    assert "ai_recommendations" in slugs
    assert "creator_tools" not in slugs
    me = svc.me_payload(1)
    assert me["current_level"] == 4
    assert me["price_rub"] == 69
    assert me["next_feature"]["slug"] == "ai_priority_speed"


def test_downgrade_preview_lists_disabled(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    svc.activate(1, 5)
    db_session.commit()
    preview = svc.preview_payload(1, 4)
    assert preview["needs_confirm"] is True
    assert any(f["slug"] == "ai_priority_speed" for f in preview["disabled"])
    assert preview["price_rub"] == 69


def test_save_custom_layout(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    features = {f.slug: f for f in svc.list_features()}
    slots = [
        {"feature_id": features["ad_free"].id, "level": 1},
        {"feature_id": features["profile_decoration"].id, "level": 2},
        {"feature_id": features["exclusive_reactions"].id, "level": 3},
        {"feature_id": features["ai_recommendations"].id, "level": 4},
        {"feature_id": features["ai_priority_speed"].id, "level": 5},
        {"feature_id": features["offline_saved_posts"].id, "level": 6},
        {"feature_id": features["creator_tools"].id, "level": 7},
        {"feature_id": features["creator_scheduled_posts"].id, "level": 8},
        {"feature_id": features["creator_analytics"].id, "level": 9},
        {"feature_id": features["priority_support"].id, "level": 10},
    ]
    svc.save_layout(1, slots)
    db_session.commit()
    assert svc.feature_level(1, features["profile_decoration"]) == 2
    assert svc.feature_level(1, features["exclusive_reactions"]) == 3


def test_legacy_pro_migrates_to_level_10(db_session):
    user = _user(db_session)
    user.subscription_type = "pro"
    user.subscription_status = "active"
    user.subscription_expires_at = datetime.utcnow() + timedelta(days=20)
    db_session.commit()
    svc = FlexSubscriptionService(db_session)
    row = svc.migrate_legacy_if_needed(1)
    assert row is not None
    assert row.current_level == 10
    assert "priority_support" in svc.unlocked_slugs(1)
    assert SubscriptionService(db_session).has_creator_access(1)


def test_expired_flex_has_no_features(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    row = svc.activate(1, 4)
    row.expires_at = datetime.utcnow() - timedelta(minutes=1)
    db_session.commit()
    assert svc.unlocked_slugs(1) == set()
    assert svc.me_payload(1)["active"] is False


def test_upgrade_quote_charges_remaining_days_only(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    row = svc.activate(1, 4)
    row.expires_at = datetime.utcnow() + timedelta(days=15)
    db_session.commit()
    quote = svc.quote_level_change(1, 6)
    assert quote["kind"] == "upgrade"
    assert quote["keep_expires"] is True
    assert quote["amount_due"] == 10.0
    assert quote["monthly_price"] == 89


def test_upgrade_payment_keeps_period_end(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    row = svc.activate(1, 4)
    ends = datetime.utcnow() + timedelta(days=15)
    row.expires_at = ends
    db_session.commit()
    svc.record_payment_subscription(
        1,
        level=6,
        amount=10.0,
        payment_provider="yookassa",
        payment_id="pay-upgrade-1",
        auto_renew=True,
    )
    db_session.commit()
    fresh = svc.get_flex(1)
    assert fresh.current_level == 6
    assert fresh.expires_at == ends
    assert "offline_saved_posts" in svc.unlocked_slugs(1)
    user = db_session.query(User).filter(User.id == 1).first()
    assert user.subscription_type == "flex"
    assert user.subscription_auto_renew is True


def test_downgrade_is_scheduled_until_renewal(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    row = svc.activate(1, 6)
    ends = datetime.utcnow() + timedelta(days=12)
    row.expires_at = ends
    db_session.commit()
    quote = svc.quote_level_change(1, 3)
    assert quote["kind"] == "downgrade"
    assert quote["needs_payment"] is False
    svc.schedule_downgrade(1, 3)
    db_session.commit()
    assert svc.current_level(1) == 6
    assert svc.get_flex(1).pending_level == 3
    assert "offline_saved_posts" in svc.unlocked_slugs(1)
    preview = svc.preview_payload(1, 3)
    assert preview["kind"] == "downgrade"
    assert preview["needs_payment"] is False

    svc.apply_renewal_period(1, expires_at=ends + timedelta(days=30), auto_renew=True)
    db_session.commit()
    assert svc.current_level(1) == 3
    assert svc.get_flex(1).pending_level is None
    assert "offline_saved_posts" not in svc.unlocked_slugs(1)


def test_has_feature_follows_level_not_bundle(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    billing = SubscriptionService(db_session)
    svc.activate(1, 3)
    db_session.commit()
    assert billing.has_feature(1, "ad_free") is True
    assert billing.has_feature(1, "exclusive_reactions") is True
    assert billing.has_feature(1, "profile_decoration") is True
    assert billing.has_feature(1, "ai_recommendations") is False
    assert billing.has_feature(1, "creator_tools") is False
    assert billing.has_feature(1, "creator_scheduled_posts") is False
    assert billing.has_ai_access(1) is False
    assert billing.has_creator_access(1) is False

    svc.activate(1, 7)
    db_session.commit()
    assert billing.has_feature(1, "ai_recommendations") is True
    assert billing.has_feature(1, "creator_tools") is True
    assert billing.has_feature(1, "creator_scheduled_posts") is False
    assert billing.has_feature(1, "creator_analytics") is False
    assert billing.has_creator_access(1) is True

    ents = billing.get_status_dict(1)["entitlements"]
    assert ents["creator_tools"] is True
    assert ents["creator_scheduled_posts"] is False
    assert ents["creator_analytics"] is False
    assert ents["chat_translation"] is False
    assert ents["larger_uploads"] is False

    svc.activate(1, 16)
    db_session.commit()
    assert billing.has_feature(1, "chat_translation") is True
    assert billing.has_feature(1, "extra_pins") is True
    assert billing.has_feature(1, "larger_uploads") is True
    assert billing.has_feature(1, "privacy_plus") is True
    assert billing.has_feature(1, "extra_folders") is True
    assert billing.has_feature(1, "message_effects") is True
    ents = billing.get_status_dict(1)["entitlements"]
    assert ents["larger_uploads"] is True
    assert ents["message_effects"] is True
    assert ents["scheduled_messages"] is False
    assert ents["story_close_friends"] is False

    svc.activate(1, 20)
    db_session.commit()
    assert billing.has_feature(1, "scheduled_messages") is True
    assert billing.has_feature(1, "chat_wallpaper") is True
    assert billing.has_feature(1, "story_viewers") is True
    assert billing.has_feature(1, "story_close_friends") is True
    assert billing.has_feature(1, "gif_search") is False
    assert billing.has_feature(1, "live_location") is False

    svc.activate(1, 24)
    db_session.commit()
    assert billing.has_feature(1, "gif_search") is True
    assert billing.has_feature(1, "animated_stickers") is True
    assert billing.has_feature(1, "group_readers") is True
    assert billing.has_feature(1, "live_location") is True
    assert billing.has_feature(1, "silent_send") is False
    assert billing.has_feature(1, "video_notes") is False

    svc.activate(1, 28)
    db_session.commit()
    assert billing.has_feature(1, "silent_send") is True
    assert billing.has_feature(1, "chat_search") is True
    assert billing.has_feature(1, "poll_quiz") is True
    assert billing.has_feature(1, "video_notes") is True
    assert billing.has_feature(1, "no_forwards") is False
    assert billing.has_feature(1, "folder_icons") is False

    svc.activate(1, 32)
    db_session.commit()
    assert billing.has_feature(1, "no_forwards") is True
    assert billing.has_feature(1, "channel_post_search") is True
    assert billing.has_feature(1, "folder_filters") is True
    assert billing.has_feature(1, "folder_icons") is True
    assert billing.has_feature(1, "voice_to_text") is False
    assert billing.has_feature(1, "profile_colors") is False

    svc.activate(1, 36)
    db_session.commit()
    assert billing.has_feature(1, "voice_to_text") is True
    assert billing.has_feature(1, "emoji_status") is True
    assert billing.has_feature(1, "checklist") is True
    assert billing.has_feature(1, "profile_colors") is True
    assert billing.has_feature(1, "any_emoji_reactions") is False
    assert billing.has_feature(1, "archive_non_contacts") is False

    svc.activate(1, 40)
    db_session.commit()
    assert billing.has_feature(1, "any_emoji_reactions") is True
    assert billing.has_feature(1, "voice_privacy") is True
    assert billing.has_feature(1, "saved_tags") is True
    assert billing.has_feature(1, "archive_non_contacts") is True
    assert billing.has_feature(1, "story_stealth") is False
    assert billing.has_feature(1, "call_privacy") is False

    svc.activate(1, 44)
    db_session.commit()
    assert billing.has_feature(1, "story_stealth") is True
    assert billing.has_feature(1, "longer_stories") is True
    assert billing.has_feature(1, "premium_stickers") is True
    assert billing.has_feature(1, "call_privacy") is True
    assert billing.has_feature(1, "extra_pinned_chats") is False
    assert billing.has_feature(1, "chat_tags") is False
    assert billing.has_feature(1, "edit_history") is False

    svc.activate(1, 48)
    db_session.commit()
    assert billing.has_feature(1, "extra_pinned_chats") is True
    assert billing.has_feature(1, "story_download") is True
    assert billing.has_feature(1, "auto_translate") is True
    assert billing.has_feature(1, "chat_tags") is True
    assert billing.has_feature(1, "default_folder") is False
    assert billing.has_feature(1, "edit_history") is False

    svc.activate(1, 52)
    db_session.commit()
    assert billing.has_feature(1, "default_folder") is True
    assert billing.has_feature(1, "hide_forward") is True
    assert billing.has_feature(1, "read_timestamps") is True
    assert billing.has_feature(1, "edit_history") is True
    assert billing.has_feature(1, "gif_favorites") is False
    assert billing.has_feature(1, "quick_replies") is False

    svc.activate(1, 60)
    db_session.commit()
    assert billing.has_feature(1, "gif_favorites") is True
    assert billing.has_feature(1, "story_archive") is True
    assert billing.has_feature(1, "story_tray_priority") is True
    assert billing.has_feature(1, "group_add_privacy") is True
    assert billing.has_feature(1, "folder_share") is True
    assert billing.has_feature(1, "story_caption_plus") is True
    assert billing.has_feature(1, "animated_avatar") is True
    assert billing.has_feature(1, "quick_replies") is True


def test_expire_and_refund_deactivate_flex(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    sub = svc.record_payment_subscription(
        1,
        level=5,
        amount=79.0,
        payment_provider="tbank",
        payment_id="pay-new-1",
        auto_renew=True,
    )
    db_session.commit()
    billing = SubscriptionService(db_session)
    assert billing.price_for_product("flex", user_id=1) == 79.0
    billing.expire_subscription(sub.id)
    assert svc.is_flex_active(1) is False
    assert db_session.query(User).filter(User.id == 1).first().subscription_type == "free"

    sub2 = svc.record_payment_subscription(
        1,
        level=4,
        amount=69.0,
        payment_provider="tbank",
        payment_id="pay-new-2",
    )
    db_session.commit()
    billing.revoke_access_after_refund(sub2)
    db_session.commit()
    assert svc.is_flex_active(1) is False


def test_yearly_new_purchase_sets_365_days(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    quote = svc.quote_level_change(1, 4, "yearly")
    assert quote["kind"] == "new"
    assert quote["period_price"] == 690
    assert quote["amount_due"] == 690
    before = datetime.utcnow()
    svc.record_payment_subscription(
        1,
        level=4,
        amount=690.0,
        payment_provider="yookassa",
        payment_id="pay-year-1",
        plan="yearly",
        auto_renew=True,
    )
    db_session.commit()
    row = svc.get_flex(1)
    assert row.plan == "yearly"
    assert row.current_level == 4
    assert row.expires_at is not None
    delta = (row.expires_at - before).total_seconds() / 86400.0
    assert 364 <= delta <= 366
    me = svc.me_payload(1)
    assert me["plan"] == "yearly"
    assert me["yearly_price_rub"] == 690


def test_monthly_to_yearly_uses_remaining_credit(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    row = svc.activate(1, 4, plan="monthly")
    row.expires_at = datetime.utcnow() + timedelta(days=15)
    db_session.commit()
    quote = svc.quote_level_change(1, 6, "yearly")
    assert quote["kind"] == "upgrade"
    assert quote["keep_expires"] is False
    assert quote["credit_rub"] == 34.5
    assert quote["amount_due"] == 855.5


def test_yearly_level_upgrade_prorates_365(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    row = svc.activate(1, 4, plan="yearly")
    row.expires_at = datetime.utcnow() + timedelta(days=180)
    db_session.commit()
    quote = svc.quote_level_change(1, 6, "yearly")
    assert quote["kind"] == "upgrade"
    assert quote["keep_expires"] is True
    assert quote["amount_due"] == 98.63
    ends = row.expires_at
    svc.record_payment_subscription(
        1,
        level=6,
        amount=98.63,
        payment_provider="yookassa",
        payment_id="pay-year-up",
        plan="yearly",
        keep_expires=True,
    )
    db_session.commit()
    fresh = svc.get_flex(1)
    assert fresh.current_level == 6
    assert fresh.plan == "yearly"
    assert fresh.expires_at == ends


def test_yearly_to_monthly_is_scheduled(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    row = svc.activate(1, 6, plan="yearly")
    ends = datetime.utcnow() + timedelta(days=80)
    row.expires_at = ends
    db_session.commit()
    quote = svc.quote_level_change(1, 6, "monthly")
    assert quote["kind"] == "downgrade"
    assert quote["needs_payment"] is False
    svc.schedule_change(1, 6, "monthly")
    db_session.commit()
    assert svc.current_level(1) == 6
    assert svc.get_flex(1).plan == "yearly"
    assert svc.effective_renewal_plan(1) == "monthly"
    svc.apply_renewal_period(1, expires_at=ends + timedelta(days=30), auto_renew=True)
    db_session.commit()
    assert svc.get_flex(1).plan == "monthly"
    assert svc.current_level(1) == 6


def test_grant_gift_sets_level_and_stacks_time(db_session):
    _user(db_session)
    other = _user(db_session, user_id=2)
    svc = FlexSubscriptionService(db_session)
    before = datetime.utcnow()
    svc.grant_gift_access(other.id, level=6, plan="monthly")
    db_session.commit()
    row = svc.get_flex(other.id)
    assert row.current_level == 6
    assert row.auto_renew is False
    assert (row.expires_at - before).total_seconds() / 86400.0 >= 29
    first_end = row.expires_at
    svc.grant_gift_access(other.id, level=4, plan="yearly")
    db_session.commit()
    fresh = svc.get_flex(other.id)
    assert fresh.current_level == 6
    assert fresh.expires_at > first_end


def test_create_gift_rejects_self(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    with pytest.raises(HTTPException) as exc:
        svc.create_gift(1, 1, level=3)
    assert exc.value.status_code == 400


def test_apply_gift_unlocks_recipient(db_session):
    sender = _user(db_session)
    recipient = _user(db_session, user_id=2)
    svc = FlexSubscriptionService(db_session)
    gift = svc.create_gift(sender.id, recipient.id, level=7, plan="yearly")
    db_session.commit()
    assert gift.amount == 990
    svc.apply_gift(gift.id, payment_provider="yookassa", payment_id="gift-1")
    db_session.commit()
    assert svc.current_level(recipient.id) == 7
    assert svc.get_flex(recipient.id).plan == "yearly"
    assert "creator_tools" in svc.unlocked_slugs(recipient.id)
    assert svc.current_level(sender.id) == 0
    stats = svc.admin_stats()
    assert stats["gifts_applied"] == 1
    assert stats["by_level"]["7"] == 1
    assert any(p["level"] == 6 for p in svc.me_payload(sender.id)["presets"])


def test_future_launch_at_hides_feature(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    feat = next(f for f in svc.list_features() if f.slug == "priority_support")
    feat.launch_at = datetime.utcnow() + timedelta(days=10)
    db_session.commit()
    slugs = {f.slug for f in svc.list_features()}
    assert "priority_support" not in slugs
    assert "ad_free" in slugs
    layout_slugs = {item["feature"].slug for item in svc.resolved_layout(1)}
    assert "priority_support" not in layout_slugs


def test_ensure_catalog_appends_missing_block_d(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    svc.ensure_catalog()
    db_session.commit()
    db_session.query(SubscriptionFeature).filter(
        SubscriptionFeature.default_level >= 11
    ).delete(synchronize_session=False)
    db_session.query(SubscriptionFeatureBlock).filter(
        SubscriptionFeatureBlock.key.in_(
            ("D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O")
        )
    ).delete(synchronize_session=False)
    db_session.commit()
    assert db_session.query(SubscriptionFeature).count() == 10
    svc.ensure_catalog()
    db_session.commit()
    slugs = {f.slug for f in svc.list_features()}
    assert "chat_translation" in slugs
    assert "message_effects" in slugs
    assert "scheduled_messages" in slugs
    assert "story_close_friends" in slugs
    assert "gif_search" in slugs
    assert "live_location" in slugs
    assert "silent_send" in slugs
    assert "video_notes" in slugs
    assert "no_forwards" in slugs
    assert "folder_icons" in slugs
    assert "voice_to_text" in slugs
    assert "profile_colors" in slugs
    assert "any_emoji_reactions" in slugs
    assert "archive_non_contacts" in slugs
    assert "story_stealth" in slugs
    assert "call_privacy" in slugs
    assert "extra_pinned_chats" in slugs
    assert "chat_tags" in slugs
    assert "default_folder" in slugs
    assert "edit_history" in slugs
    assert "gif_favorites" in slugs
    assert "quick_replies" in slugs
    assert {b.key for b in svc.list_blocks()} == {
        "A",
        "B",
        "C",
        "D",
        "E",
        "F",
        "G",
        "H",
        "I",
        "J",
        "K",
        "L",
        "M",
        "N",
        "O",
    }
    me = svc.me_payload(1)
    assert me["max_level"] == 60
    assert any(p["level"] == 16 for p in me["presets"])
    assert any(p["level"] == 20 for p in me["presets"])
    assert any(p["level"] == 24 for p in me["presets"])
    assert any(p["level"] == 28 for p in me["presets"])
    assert any(p["level"] == 32 for p in me["presets"])
    assert any(p["level"] == 36 for p in me["presets"])
    assert any(p["level"] == 40 for p in me["presets"])
    assert any(p["level"] == 44 for p in me["presets"])
    assert any(p["level"] == 48 for p in me["presets"])
    assert any(p["level"] == 52 for p in me["presets"])
    assert any(p["level"] == 56 for p in me["presets"])
    assert any(p["level"] == 60 for p in me["presets"])


def test_privacy_plus_lets_hidden_viewer_see_last_seen(db_session):
    from app.services.last_seen_privacy import (
        PRIVACY_EVERYBODY,
        PRIVACY_NOBODY,
        can_viewer_see_last_seen,
    )

    owner = _user(db_session, 1)
    viewer = _user(db_session, 2)
    owner.last_seen_privacy = PRIVACY_EVERYBODY
    viewer.last_seen_privacy = PRIVACY_NOBODY
    viewer.show_last_seen = False
    db_session.commit()
    assert can_viewer_see_last_seen(db_session, owner, viewer.id) is False
    FlexSubscriptionService(db_session).activate(viewer.id, 14)
    db_session.commit()
    assert can_viewer_see_last_seen(db_session, owner, viewer.id) is True
    assert SubscriptionService(db_session).has_feature(viewer.id, "privacy_plus") is True


def test_higher_flex_level_sees_hidden_last_seen(db_session):
    from app.services.last_seen_privacy import (
        PRIVACY_NOBODY,
        can_viewer_see_last_seen,
    )

    owner = _user(db_session, 1)
    viewer = _user(db_session, 2)
    peer = _user(db_session, 3)
    owner.last_seen_privacy = PRIVACY_NOBODY
    owner.show_last_seen = False
    db_session.commit()
    svc = FlexSubscriptionService(db_session)
    svc.activate(owner.id, 4)
    svc.activate(viewer.id, 6)
    svc.activate(peer.id, 4)
    db_session.commit()
    assert can_viewer_see_last_seen(db_session, owner, viewer.id) is True
    assert can_viewer_see_last_seen(db_session, owner, peer.id) is False
    assert can_viewer_see_last_seen(db_session, owner, owner.id) is True


def test_folder_filters_need_premium_keys():
    from app.services.chat_service import ChatService

    assert ChatService._folder_filters_need_premium(None) is False
    assert ChatService._folder_filters_need_premium({}) is False
    assert ChatService._folder_filters_need_premium({"groups": True, "direct": True}) is False
    assert ChatService._folder_filters_need_premium({"contacts": True}) is True
    assert ChatService._folder_filters_need_premium({"unread_only": True}) is True
    assert ChatService._folder_filters_need_premium({"exclude_bots": True}) is True
