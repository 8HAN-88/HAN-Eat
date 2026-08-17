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


def test_expired_flex_has_no_features(db_session):
    _user(db_session)
    svc = FlexSubscriptionService(db_session)
    row = svc.activate(1, 4)
    row.expires_at = datetime.utcnow() - timedelta(minutes=1)
    db_session.commit()
    assert svc.unlocked_slugs(1) == set()
    assert svc.me_payload(1)["active"] is False
