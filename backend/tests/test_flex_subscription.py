from datetime import datetime, timedelta

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.models.flex_subscription import (
    SubscriptionFeature,
    SubscriptionFeatureBlock,
    UserFlexSlot,
    UserFlexSubscription,
)
from app.models.subscription import Subscription
from app.models.user import User
from app.services.flex_subscription_service import (
    FlexMoveError,
    FlexSubscriptionService,
    price_for_level,
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


def test_catalog_seed_and_default_layout(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    layout = svc.resolved_layout(1)
    assert len(layout) == 10
    assert layout[0]["feature"].slug == "ad_free"
    assert layout[0]["level"] == 1
    assert layout[-1]["feature"].slug == "priority_support"
    assert layout[-1]["level"] == 10


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
