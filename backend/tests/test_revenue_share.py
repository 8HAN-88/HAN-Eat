from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.revenue_share import split_kopecks
from app.models.revenue_share import RevenueShareLedger
from app.models.user import User
from app.services.revenue_share_service import (
    RevenueShareError,
    RevenueShareService,
)


@pytest.fixture()
def db_session():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    from app.core.database import Base

    Base.metadata.create_all(
        bind=engine,
        tables=[User.__table__, RevenueShareLedger.__table__],
    )
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def _user(db, user_id: int, **kwargs) -> User:
    user = User(
        id=user_id,
        email=f"u{user_id}@ex.com",
        password_hash="x",
        name=f"User {user_id}",
        username=f"user{user_id}",
        **kwargs,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def test_split_extra_ads_with_referrer():
    parts = split_kopecks(
        10000,
        source="ads",
        extra_ads=True,
        has_referrer=True,
    )
    assert parts["net"] == 7000
    assert parts["user"] == 3500
    assert parts["referrer"] == 1750
    assert parts["company"] == 1750


def test_split_without_extra_ads_keeps_referrer_rate():
    parts = split_kopecks(
        10000,
        source="ads",
        extra_ads=False,
        has_referrer=True,
    )
    assert parts["user"] == 0
    assert parts["referrer"] == 1750
    assert parts["company"] == 5250


def test_subscription_never_pays_the_payer():
    parts = split_kopecks(
        10000,
        source="subscription",
        extra_ads=True,
        has_referrer=True,
    )
    assert parts["user"] == 0
    assert parts["referrer"] == 1750


def test_apply_code_and_accrue(db_session):
    referrer = _user(db_session, 1)
    viewer = _user(db_session, 2, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(referrer)
    db_session.commit()
    svc.apply_code(viewer, code)
    svc.set_extra_ads(viewer, True)
    db_session.commit()
    svc.accrue_ad_event(viewer_id=2, kind="click", reference_id=11)
    db_session.commit()
    rows = db_session.query(RevenueShareLedger).all()
    assert len(rows) == 2
    by_role = {row.role: row.share_kopecks for row in rows}
    assert by_role["viewer"] == 70
    assert by_role["referrer"] == 35


def test_reject_self_code(db_session):
    user = _user(db_session, 3, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(user)
    db_session.commit()
    with pytest.raises(RevenueShareError):
        svc.apply_code(user, code)


def test_apply_username_invite_ref(db_session):
    referrer = _user(db_session, 8, created_at=datetime.utcnow())
    viewer = _user(db_session, 9, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    svc.apply_code(viewer, referrer.username)
    db_session.commit()
    db_session.refresh(viewer)
    assert viewer.referred_by_user_id == referrer.id


def test_snapshot_uses_invite_share_url(db_session):
    user = _user(db_session, 6)
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(user)
    snap = svc.snapshot(user)
    assert snap["share_url"] == f"https://haneat.app/invite?ref={code}"
    assert snap["referral_code"] == code


def test_apply_code_accepts_aware_created_at(db_session):
    referrer = _user(db_session, 10)
    viewer = _user(
        db_session,
        11,
        created_at=datetime.now(timezone.utc),
    )
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(referrer)
    db_session.commit()
    svc.apply_code(viewer, code)
    db_session.commit()
    db_session.refresh(viewer)
    assert viewer.referred_by_user_id == referrer.id


def test_apply_uid_invite_ref(db_session):
    referrer = _user(db_session, 12, created_at=datetime.utcnow())
    viewer = _user(db_session, 13, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    svc.apply_code(viewer, f"U{referrer.id}")
    db_session.commit()
    db_session.refresh(viewer)
    assert viewer.referred_by_user_id == referrer.id


def test_old_account_cannot_apply_code(db_session):
    referrer = _user(db_session, 4)
    old = _user(
        db_session,
        5,
        created_at=datetime.utcnow() - timedelta(days=20),
    )
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(referrer)
    db_session.commit()
    with pytest.raises(RevenueShareError):
        svc.apply_code(old, code)
