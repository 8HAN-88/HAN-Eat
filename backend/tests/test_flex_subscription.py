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
    assert price_for_level(18) == 209


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
    defaults = [int(item["level"]) for item in layout]
    assert len(defaults) == 18
    assert defaults == list(range(1, 19))
    assert any(item["feature"].slug == "ad_free" and item["level"] == 1 for item in layout)
    assert any(
        item["feature"].slug == "priority_support" and item["level"] == 17
        for item in layout
    )
    assert any(item["feature"].slug == "pro" and item["level"] == 18 for item in layout)


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
        svc.move_feature(1, reactions.id, 8)


def test_activate_unlocks_assigned_levels(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    svc.activate(1, 7)
    db_session.commit()
    slugs = svc.unlocked_slugs(1)
    assert "ad_free" in slugs
    assert "ai_recommendations" in slugs
    assert "creator_tools" not in slugs
    me = svc.me_payload(1)
    assert me["current_level"] == 7
    assert me["price_rub"] == 99
    assert me["next_feature"]["slug"] == "ai_priority_speed"
    assert me["max_level"] == 18


def test_downgrade_preview_lists_disabled(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    svc.activate(1, 8)
    db_session.commit()
    preview = svc.preview_payload(1, 7)
    assert preview["needs_confirm"] is True
    assert any(f["slug"] == "ai_priority_speed" for f in preview["disabled"])
    assert preview["price_rub"] == 99


def test_save_custom_layout(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    features = {f.slug: f for f in svc.list_features()}
    slots = [
        {
            "feature_id": feat.id,
            "level": 2 if slug == "profile_decoration" else 5 if slug == "premium_badge" else int(feat.default_level),
        }
        for slug, feat in features.items()
    ]
    svc.save_layout(1, slots)
    db_session.commit()
    assert svc.feature_level(1, features["profile_decoration"]) == 2
    assert svc.feature_level(1, features["premium_badge"]) == 5


def test_expired_flex_has_no_features(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    row = svc.activate(1, 7)
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
    svc.activate(1, 9)
    db_session.commit()
    slugs = svc.unlocked_slugs(1)
    assert AI_FEATURE_SLUGS <= slugs
    assert slugs.isdisjoint(CREATOR_FEATURE_SLUGS)
    assert slugs.isdisjoint(PRO_FEATURE_SLUGS)


def test_classic_creator_level_unlocks_full_creator_pack(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    svc.activate(1, 16)
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
    assert next_slugs == {"premium_badge"}


def test_multiple_features_can_share_a_level(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    reactions = next(f for f in svc.list_features() if f.slug == "exclusive_reactions")
    svc.move_feature(1, reactions.id, 4)
    db_session.commit()
    at_four = [
        item["feature"].slug
        for item in svc.resolved_layout(1)
        if int(item["level"]) == 4
    ]
    assert "exclusive_reactions" in at_four
    assert "larger_uploads" in at_four


def test_flex_entitlements_follow_unlocked_slugs(db_session):
    from app.services.subscription_service import SubscriptionService

    _user(db_session)
    FlexSubscriptionService(db_session).activate(1, 2)
    db_session.commit()
    sub = SubscriptionService(db_session)
    assert sub.has_entitlement(1, "ad_free")
    assert sub.has_entitlement(1, "premium_badge")
    assert not sub.has_entitlement(1, "exclusive_reactions")
    assert not sub.has_entitlement(1, "creator_tools")
    assert not sub.has_pro_access(1)
    status = sub.get_status_dict(1)
    assert status["is_active"] is True
    assert status["entitlements"]["ad_free"] is True
    assert status["entitlements"].get("creator_tools") is not True


def test_flex_level_10_unlocks_pro_support(db_session):
    from app.services.subscription_service import SubscriptionService

    _user(db_session)
    FlexSubscriptionService(db_session).activate(1, 18)
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
    from app.core.entitlements import ALL_CATALOG_SLUGS

    for slug in ALL_CATALOG_SLUGS:
        assert sub.has_entitlement(1, slug)


def test_flex_level_7_does_not_unlock_schedule_or_promote(db_session):
    from app.services.post_publish_service import require_creator_for_schedule
    from app.services.subscription_service import SubscriptionService

    user = _user(db_session)
    FlexSubscriptionService(db_session).activate(1, 10)
    db_session.commit()
    sub = SubscriptionService(db_session)
    assert sub.has_entitlement(1, "creator_tools")
    assert not sub.has_entitlement(1, "creator_badge")
    assert not sub.has_entitlement(1, "creator_scheduled_posts")
    assert not sub.has_entitlement(1, "creator_promotion")
    assert not sub.has_entitlement(1, "creator_pinned")
    assert not sub.has_entitlement(1, "creator_analytics")
    future = datetime.utcnow() + timedelta(days=1)
    with pytest.raises(HTTPException) as err:
        require_creator_for_schedule(db_session, user, future)
    assert err.value.status_code == 403

    FlexSubscriptionService(db_session).activate(1, 12)
    db_session.commit()
    require_creator_for_schedule(db_session, user, future)
    assert sub.has_entitlement(1, "creator_scheduled_posts")
    assert not sub.has_entitlement(1, "creator_promotion")
    assert not sub.has_entitlement(1, "creator_pinned")


def test_flex_level_4_unlocks_ai_recommendations_only(db_session):
    from app.services.subscription_service import SubscriptionService

    _user(db_session)
    FlexSubscriptionService(db_session).activate(1, 7)
    db_session.commit()
    sub = SubscriptionService(db_session)
    assert sub.has_entitlement(1, "ai_recommendations")
    assert not sub.has_entitlement(1, "ai_priority_speed")
    assert not sub.has_entitlement(1, "offline_saved_posts")
    assert sub.has_ai_access(1)


def test_ensure_catalog_updates_existing_levels(db_session):
    svc = FlexSubscriptionService(db_session)
    svc.ensure_catalog()
    db_session.commit()
    pro = db_session.query(SubscriptionFeature).filter_by(slug="pro").one()
    pro.default_level = 10
    pro.min_level = 10
    pro.max_level = 10
    block_c = db_session.query(SubscriptionFeatureBlock).filter_by(key="C").one()
    block_c.max_level = 10
    db_session.commit()
    svc.ensure_catalog()
    db_session.commit()
    pro = db_session.query(SubscriptionFeature).filter_by(slug="pro").one()
    assert pro.default_level == 18
    assert pro.max_level == 18
    assert db_session.query(SubscriptionFeatureBlock).filter_by(key="C").one().max_level == 18


def test_ensure_catalog_remaps_compact_subscriber(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    svc.ensure_catalog()
    pro = db_session.query(SubscriptionFeature).filter_by(slug="pro").one()
    pro.default_level = 10
    pro.min_level = 10
    pro.max_level = 10
    row = svc.activate(1, 10)
    row.current_level = 10
    db_session.commit()
    svc.ensure_catalog()
    db_session.commit()
    assert svc.get_flex(1).current_level == 18
    assert db_session.query(SubscriptionFeature).filter_by(slug="pro").one().default_level == 18


def test_remap_compact_subscribers_keeps_pro_at_top(db_session):
    from app.services.flex_subscription_service import remap_compact_level

    assert remap_compact_level(10) == 18
    assert remap_compact_level(7) == 11
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    svc.ensure_catalog()
    row = svc.activate(1, 10)
    row.current_level = 10
    db_session.commit()
    assert svc.remap_compact_subscribers() == 1
    db_session.commit()
    assert svc.get_flex(1).current_level == 18
    assert svc.remap_compact_subscribers() == 0
