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
from app.core.entitlements import subscription_entitlements
from app.services.flex_subscription_service import (
    AI_FEATURE_SLUGS,
    CREATOR_FEATURE_SLUGS,
    DEFAULT_FEATURES,
    PRO_FEATURE_SLUGS,
    FlexMoveError,
    FlexSubscriptionService,
    price_for_level,
)


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
    slugs = {item["feature"].slug for item in layout}
    expected = {row["slug"] for row in DEFAULT_FEATURES}
    assert slugs == expected
    assert "creator_promotion" in slugs
    assert "pro" in slugs
    assert "larger_uploads" in slugs
    assert any(item["feature"].slug == "ad_free" and item["level"] == 1 for item in layout)
    assert any(
        item["feature"].slug == "priority_support" and item["level"] == 10
        for item in layout
    )


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
    for slug, feat in features.items():
        if slug in {
            "ad_free",
            "profile_decoration",
            "exclusive_reactions",
            "ai_recommendations",
            "ai_priority_speed",
            "offline_saved_posts",
            "creator_tools",
            "creator_scheduled_posts",
            "creator_analytics",
            "priority_support",
        }:
            continue
        slots.append({"feature_id": feat.id, "level": int(feat.default_level)})
    svc.save_layout(1, slots)
    db_session.commit()
    assert svc.feature_level(1, features["profile_decoration"]) == 2
    assert svc.feature_level(1, features["exclusive_reactions"]) == 3


def test_expired_flex_has_no_features(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    row = svc.activate(1, 4)
    row.expires_at = datetime.utcnow() - timedelta(minutes=1)
    db_session.commit()
    assert svc.unlocked_slugs(1) == set()
    assert svc.me_payload(1)["active"] is False


def test_ensure_catalog_adds_missing_features(db_session):
    svc = FlexSubscriptionService(db_session)
    svc.ensure_catalog()
    db_session.commit()
    first = db_session.query(SubscriptionFeature).filter_by(slug="ad_free").one()
    db_session.delete(
        db_session.query(SubscriptionFeature).filter_by(slug="creator_promotion").one()
    )
    db_session.commit()
    svc.ensure_catalog()
    db_session.commit()
    assert (
        db_session.query(SubscriptionFeature).filter_by(slug="creator_promotion").one()
    )
    assert db_session.query(SubscriptionFeature).filter_by(slug="ad_free").one().id == first.id


def test_catalog_covers_classic_entitlements(db_session):
    slugs = {row["slug"] for row in DEFAULT_FEATURES}
    expected = set(subscription_entitlements("pro")) - {"offline_recipes", "is_plus"}
    assert expected <= slugs


def test_classic_ai_level_unlocks_full_ai_pack(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    svc.activate(1, 6)
    db_session.commit()
    slugs = svc.unlocked_slugs(1)
    assert AI_FEATURE_SLUGS <= slugs
    assert slugs.isdisjoint(CREATOR_FEATURE_SLUGS)
    assert slugs.isdisjoint(PRO_FEATURE_SLUGS)


def test_classic_creator_level_unlocks_full_creator_pack(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    svc.activate(1, 9)
    db_session.commit()
    slugs = svc.unlocked_slugs(1)
    assert AI_FEATURE_SLUGS <= slugs
    assert CREATOR_FEATURE_SLUGS <= slugs
    assert slugs.isdisjoint(PRO_FEATURE_SLUGS)


def test_preview_lists_all_next_features(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    preview = svc.preview_payload(1, 1)
    next_slugs = {item["slug"] for item in preview["next_features"]}
    assert "exclusive_reactions" in next_slugs
    assert "larger_uploads" in next_slugs


def test_multiple_features_can_share_a_level(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    badge = next(f for f in svc.list_features() if f.slug == "premium_badge")
    svc.move_feature(1, badge.id, 2)
    db_session.commit()
    at_two = [
        item["feature"].slug
        for item in svc.resolved_layout(1)
        if int(item["level"]) == 2
    ]
    assert "premium_badge" in at_two
    assert "larger_uploads" in at_two


def test_flex_entitlements_follow_unlocked_slugs(db_session):
    from app.services.subscription_service import SubscriptionService

    _user(db_session)
    FlexSubscriptionService(db_session).activate(1, 1)
    db_session.commit()
    sub = SubscriptionService(db_session)
    assert sub.has_entitlement(1, "ad_free")
    assert sub.has_entitlement(1, "premium_badge")
    assert not sub.has_entitlement(1, "creator_tools")
    assert not sub.has_pro_access(1)
    status = sub.get_status_dict(1)
    assert status["is_active"] is True
    assert status["entitlements"]["ad_free"] is True
    assert status["entitlements"].get("creator_tools") is not True


def test_flex_level_10_unlocks_pro_support(db_session):
    from app.services.subscription_service import SubscriptionService

    _user(db_session)
    FlexSubscriptionService(db_session).activate(1, 10)
    db_session.commit()
    sub = SubscriptionService(db_session)
    assert sub.has_pro_access(1)
    assert sub.has_entitlement(1, "priority_support")
    assert sub.has_entitlement(1, "pro")
    assert sub.has_creator_access(1)
    assert sub.has_ai_access(1)
    status = sub.get_status_dict(1)
    assert status["subscription_type"] == "pro"
    assert status["has_creator"] is True
    assert status["has_ai"] is True
