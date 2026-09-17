from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.revenue_share import (
    KOPECKS_PER_STAR,
    MIN_CARD_PAYOUT_KOPECKS,
    payment_reference_id,
    split_kopecks,
)
from app.models.paid_features import StarTransaction
from app.models.revenue_share import PartnerPayoutRequest, RevenueShareLedger
from app.models.subscription import Subscription
from app.models.user import User
from app.services.revenue_share_service import (
    RevenueShareError,
    RevenueShareService,
    extract_referral,
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
        tables=[
            User.__table__,
            PartnerPayoutRequest.__table__,
            RevenueShareLedger.__table__,
            Subscription.__table__,
            StarTransaction.__table__,
        ],
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


def test_apply_lowercase_official_code(db_session):
    referrer = _user(db_session, 17, created_at=datetime.utcnow())
    viewer = _user(db_session, 18, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(referrer)
    db_session.commit()
    svc.apply_code(viewer, code.lower())
    db_session.commit()
    db_session.refresh(viewer)
    assert viewer.referred_by_user_id == referrer.id


def test_reject_banned_referrer(db_session):
    referrer = _user(db_session, 19, banned_at=datetime.utcnow())
    viewer = _user(db_session, 20, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(referrer)
    db_session.commit()
    with pytest.raises(RevenueShareError):
        svc.apply_code(viewer, code)


def test_reject_deleted_referrer(db_session):
    referrer = _user(db_session, 21, deleted_at=datetime.utcnow())
    viewer = _user(db_session, 22, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(referrer)
    db_session.commit()
    with pytest.raises(RevenueShareError):
        svc.apply_code(viewer, code)


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


def test_attach_after_signup_binds_and_issues_code(db_session):
    referrer = _user(db_session, 14)
    viewer = _user(db_session, 15, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(referrer)
    db_session.commit()
    svc.attach_after_signup(viewer, code)
    db_session.commit()
    db_session.refresh(viewer)
    assert viewer.referred_by_user_id == referrer.id
    assert (viewer.referral_code or "").strip()


def test_attach_after_signup_invalid_code_still_issues_own(db_session):
    viewer = _user(db_session, 16, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    svc.attach_after_signup(viewer, "NOPECODE")
    db_session.commit()
    db_session.refresh(viewer)
    assert viewer.referred_by_user_id is None
    assert (viewer.referral_code or "").strip()


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


def test_extract_referral_unwraps_share_wrappers():
    assert extract_referral("ABC12XYZ") == "ABC12XYZ"
    assert extract_referral("@alice") == "alice"
    assert (
        extract_referral("https://haneat.app/invite?ref=ABC12XYZ") == "ABC12XYZ"
    )
    assert (
        extract_referral("https://www.haneat.app/app/#/invite?ref=ABC12XYZ")
        == "ABC12XYZ"
    )
    assert (
        extract_referral(
            "https://wa.me/?text="
            + "https%3A%2F%2Fhaneat.app%2Finvite%3Fref%3DABC12XYZ"
        )
        == "ABC12XYZ"
    )
    assert (
        extract_referral("Смотри: https://haneat.app/invite?ref=ABC12XYZ")
        == "ABC12XYZ"
    )
    assert (
        extract_referral("https://haneat.app/invite?REF=ABC12XYZ") == "ABC12XYZ"
    )
    assert (
        extract_referral("https://haneat.app/invite?referral=ABC12XYZ")
        == "ABC12XYZ"
    )
    assert (
        extract_referral("https://haneat.app/app/#/invite?REF=ABC12XYZ")
        == "ABC12XYZ"
    )
    assert extract_referral("https://haneat.app/app/") is None
    assert extract_referral("https://haneat.app/") is None
    assert extract_referral("https://haneat.app/invite") is None
    assert (
        extract_referral("https://haneat.app/invite?utm=1&amp;ref=ABC12XYZ")
        == "ABC12XYZ"
    )
    assert extract_referral("https://haneat.app/invite?ref=ABC12XYZ.") == "ABC12XYZ"
    assert extract_referral("ABC\u200b12XYZ") == "ABC12XYZ"
    assert extract_referral("https://haneat.app/invite/ABC12XYZ") == "ABC12XYZ"
    assert (
        extract_referral("https://haneat.app/app/invite/ABC12XYZ") == "ABC12XYZ"
    )


def test_apply_invite_url_and_whatsapp_wrap(db_session):
    referrer = _user(db_session, 23, created_at=datetime.utcnow())
    viewer = _user(db_session, 24, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(referrer)
    db_session.commit()
    svc.apply_code(viewer, f"https://haneat.app/invite?ref={code}")
    db_session.commit()
    db_session.refresh(viewer)
    assert viewer.referred_by_user_id == referrer.id


def test_reject_bot_viewer_apply(db_session):
    referrer = _user(db_session, 44, created_at=datetime.utcnow())
    bot = _user(db_session, 45, is_bot=True, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(referrer)
    db_session.commit()
    with pytest.raises(RevenueShareError):
        svc.apply_code(bot, code)


def test_referred_count_skips_bots(db_session):
    referrer = _user(db_session, 46, created_at=datetime.utcnow())
    human = _user(db_session, 47, created_at=datetime.utcnow())
    bot = _user(db_session, 48, is_bot=True, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(referrer)
    db_session.commit()
    svc.apply_code(human, code)
    bot.referred_by_user_id = referrer.id
    db_session.commit()
    snap = svc.snapshot(referrer)
    assert snap["referred_count"] == 1


def test_reject_bot_referrer(db_session):
    referrer = _user(db_session, 25, is_bot=True, created_at=datetime.utcnow())
    viewer = _user(db_session, 26, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(referrer)
    db_session.commit()
    with pytest.raises(RevenueShareError):
        svc.apply_code(viewer, code)


def test_banned_referrer_stops_accrual(db_session):
    referrer = _user(db_session, 27)
    viewer = _user(db_session, 28, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(referrer)
    db_session.commit()
    svc.apply_code(viewer, code)
    svc.set_extra_ads(viewer, True)
    db_session.commit()
    referrer.banned_at = datetime.utcnow()
    db_session.commit()
    svc.accrue_ad_event(viewer_id=28, kind="click", reference_id=99)
    db_session.commit()
    rows = db_session.query(RevenueShareLedger).all()
    assert [row.role for row in rows] == ["viewer"]


def test_banned_viewer_does_not_accrue(db_session):
    referrer = _user(db_session, 30)
    viewer = _user(db_session, 31, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(referrer)
    db_session.commit()
    svc.apply_code(viewer, code)
    svc.set_extra_ads(viewer, True)
    viewer.banned_at = datetime.utcnow()
    db_session.commit()
    svc.accrue_ad_event(viewer_id=31, kind="click", reference_id=77)
    db_session.commit()
    assert db_session.query(RevenueShareLedger).count() == 0


def test_snapshot_includes_referrer_username(db_session):
    referrer = _user(db_session, 32)
    viewer = _user(db_session, 33, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(referrer)
    db_session.commit()
    svc.apply_code(viewer, code)
    db_session.commit()
    snap = svc.snapshot(viewer)
    assert snap["referred_by"]["username"] == referrer.username
    assert snap["referred_by"]["code"] == code
    assert snap["referred_by"]["id"] == referrer.id


def test_snapshot_omits_empty_share_url(db_session, monkeypatch):
    user = _user(db_session, 29)

    def _no_code(_self, _user):
        return ""

    monkeypatch.setattr(RevenueShareService, "ensure_code", _no_code)
    svc = RevenueShareService(db_session)
    snap = svc.snapshot(user)
    assert snap["share_url"] == ""
    assert snap["referral_code"] in (None, "")


def test_void_subscription_share_after_refund(db_session):
    referrer = _user(db_session, 34)
    payer = _user(db_session, 35, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(referrer)
    db_session.commit()
    svc.apply_code(payer, code)
    db_session.commit()
    svc.accrue_subscription(payer_id=35, amount_rub=100, reference_id=payment_reference_id("pay_1"))
    db_session.commit()
    assert db_session.query(RevenueShareLedger).count() == 1
    cleared = svc.void_subscription_share("pay_1")
    db_session.commit()
    assert cleared == 1
    row = db_session.query(RevenueShareLedger).one()
    assert row.status == "void"
    snap = svc.snapshot(referrer)
    assert snap["pending_kopecks"] == 0
    assert snap["available_kopecks"] == 0


def test_release_ready_accepts_aware_available_at(db_session):
    user = _user(db_session, 36)
    svc = RevenueShareService(db_session)
    svc.ensure_code(user)
    db_session.add(
        RevenueShareLedger(
            beneficiary_user_id=user.id,
            role="referrer",
            source="subscription",
            subject_user_id=user.id,
            referrer_user_id=user.id,
            extra_ads=False,
            gross_kopecks=10000,
            net_kopecks=7000,
            share_kopecks=1750,
            status="pending",
            available_at=datetime.now(timezone.utc) - timedelta(days=1),
            reference_type="subscription",
            reference_id=7,
        )
    )
    db_session.commit()
    snap = svc.snapshot(user)
    assert snap["available_kopecks"] == 1750
    assert snap["pending_kopecks"] == 0


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


def test_process_payment_succeeded_retries_share_when_already_linked(db_session):
    from app.services.payment_success_handler import process_payment_succeeded

    referrer = _user(db_session, 40)
    payer = _user(db_session, 41, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(referrer)
    db_session.commit()
    svc.apply_code(payer, code)
    db_session.commit()
    db_session.add(
        Subscription(
            user_id=payer.id,
            plan="monthly",
            product="pro",
            status="active",
            payment_provider="tbank",
            payment_provider_subscription_id="pay_retry_1",
            amount=199,
            currency="RUB",
            refund_status="none",
        )
    )
    db_session.commit()
    process_payment_succeeded(
        db_session,
        payment_provider="tbank",
        payment_id="pay_retry_1",
        payment_info={
            "paid": True,
            "amount": 199,
            "metadata": {"product": "pro"},
        },
    )
    assert db_session.query(RevenueShareLedger).count() == 1
    process_payment_succeeded(
        db_session,
        payment_provider="tbank",
        payment_id="pay_retry_1",
        payment_info={
            "paid": True,
            "amount": 199,
            "metadata": {"product": "pro"},
        },
    )
    assert db_session.query(RevenueShareLedger).count() == 1
    row = db_session.query(RevenueShareLedger).one()
    assert row.beneficiary_user_id == referrer.id
    assert row.source == "subscription"
    assert row.status == "pending"


def test_process_payment_succeeded_retry_skips_stars(db_session):
    from app.services.payment_success_handler import process_payment_succeeded

    referrer = _user(db_session, 42)
    payer = _user(db_session, 43, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(referrer)
    db_session.commit()
    svc.apply_code(payer, code)
    db_session.commit()
    db_session.add(
        Subscription(
            user_id=payer.id,
            plan="monthly",
            product="pro",
            status="active",
            payment_provider="tbank",
            payment_provider_subscription_id="pay_stars_1",
            amount=99,
            currency="RUB",
            refund_status="none",
        )
    )
    db_session.commit()
    process_payment_succeeded(
        db_session,
        payment_provider="tbank",
        payment_id="pay_stars_1",
        payment_info={
            "paid": True,
            "amount": 99,
            "metadata": {"product": "stars"},
        },
    )
    assert db_session.query(RevenueShareLedger).count() == 0


def test_login_attaches_referral_before_email_verification_gate():
    src = Path(__file__).resolve().parents[1].joinpath("app/api/v1/auth.py").read_text()
    start = src.index("async def login(")
    end = src.index("\nasync def ", start + 1)
    login = src[start:end]
    assert login.index("_attach_referral(db, user, request.referral_code)") < login.index(
        "REQUIRE_EMAIL_VERIFICATION"
    )


def test_tbank_webhook_voids_refunded_and_reversed_shares():
    src = Path(__file__).resolve().parents[1].joinpath("app/api/v1/payments.py").read_text()
    start = src.index("async def tbank_webhook(")
    end = src.index("\n@router.", start + 1)
    hook = src[start:end]
    assert '"REVERSED"' in hook
    assert '"REFUNDED"' in hook
    assert '"PARTIAL_REFUNDED"' in hook
    assert "_void_referral_share(str(payment_id))" in hook


def test_yookassa_refund_voids_even_if_already_marked():
    src = Path(__file__).resolve().parents[1].joinpath("app/api/v1/payments.py").read_text()
    start = src.index("async def yookassa_webhook(")
    end = src.index("\n@router.", start + 1)
    hook = src[start:end]
    void_at = hook.index("_void_referral_share(str(payment_id))")
    marked = hook.index('sub.refund_status != "refunded"')
    assert void_at < marked


def test_stripe_invoice_accrues_and_charge_refund_voids():
    payments = Path(__file__).resolve().parents[1].joinpath("app/api/v1/payments.py").read_text()
    stripe_svc = (
        Path(__file__).resolve().parents[1].joinpath("app/services/payment_service.py").read_text()
    )
    assert "invoice_id" in stripe_svc
    assert 'event_type == "charge.refunded"' in stripe_svc
    assert "_accrue_subscription_share" in payments
    assert 'result.get("action") == "refund_succeeded"' in payments


def _available_share(db, user, share, ref):
    db.add(
        RevenueShareLedger(
            beneficiary_user_id=user.id,
            role="referrer",
            source="subscription",
            subject_user_id=user.id,
            referrer_user_id=user.id,
            extra_ads=False,
            gross_kopecks=share * 4,
            net_kopecks=share * 3,
            share_kopecks=share,
            status="available",
            available_at=datetime.utcnow() - timedelta(days=1),
            reference_type="subscription",
            reference_id=ref,
        )
    )
    db.commit()


def test_convert_to_stars_and_keep_remainder(db_session):
    user = _user(db_session, 60)
    svc = RevenueShareService(db_session)
    svc.ensure_code(user)
    _available_share(db_session, user, 1750, 101)
    payout = svc.convert_to_stars(user)
    db_session.commit()
    assert payout.kind == "stars"
    assert payout.status == "paid"
    assert payout.amount_stars == 1750 // KOPECKS_PER_STAR
    assert payout.amount_kopecks == payout.amount_stars * KOPECKS_PER_STAR
    snap = svc.snapshot(user)
    leftover = 1750 - payout.amount_kopecks
    assert snap["available_kopecks"] == leftover
    assert snap["paid_kopecks"] == payout.amount_kopecks
    assert snap["convertible_stars"] == leftover // KOPECKS_PER_STAR
    stars = db_session.query(StarTransaction).filter(StarTransaction.user_id == user.id).one()
    assert stars.amount == payout.amount_stars
    assert stars.type == "partner_payout"
    row = (
        db_session.query(RevenueShareLedger)
        .filter(RevenueShareLedger.status == "paid")
        .one()
    )
    assert row.payout_request_id == payout.id
    assert row.share_kopecks == payout.amount_kopecks


def test_convert_to_stars_requires_one_star(db_session):
    user = _user(db_session, 61)
    svc = RevenueShareService(db_session)
    _available_share(db_session, user, 79, 102)
    with pytest.raises(RevenueShareError):
        svc.convert_to_stars(user)


def test_card_payout_hold_reject_and_approve(db_session):
    user = _user(db_session, 62)
    admin = _user(db_session, 63, is_admin=True)
    svc = RevenueShareService(db_session)
    _available_share(db_session, user, 30000, 201)
    _available_share(db_session, user, 25000, 202)
    with pytest.raises(RevenueShareError):
        svc.request_card_payout(
            user,
            amount_kopecks=MIN_CARD_PAYOUT_KOPECKS - 1,
            phone="+79001234567",
            recipient_name="Иван Петров",
        )
    payout = svc.request_card_payout(
        user,
        amount_kopecks=MIN_CARD_PAYOUT_KOPECKS,
        phone="8 900 123-45-67",
        recipient_name="Иван Петров",
    )
    db_session.commit()
    assert payout.status == "pending"
    assert payout.phone == "+79001234567"
    snap = svc.snapshot(user)
    assert snap["available_kopecks"] == 5000
    assert snap["payout_hold_kopecks"] == MIN_CARD_PAYOUT_KOPECKS
    assert snap["available_kopecks"] + snap["payout_hold_kopecks"] == 55000
    rejected = svc.review_payout(payout.id, reviewer_user_id=admin.id, approve=False)
    db_session.commit()
    assert rejected.status == "rejected"
    snap = svc.snapshot(user)
    assert snap["available_kopecks"] == 55000
    assert snap["payout_hold_kopecks"] == 0
    payout2 = svc.request_card_payout(
        user,
        amount_kopecks=None,
        phone="79001234567",
        recipient_name="Иван Петров",
    )
    db_session.commit()
    approved = svc.review_payout(payout2.id, reviewer_user_id=admin.id, approve=True)
    db_session.commit()
    assert approved.status == "paid"
    snap = svc.snapshot(user)
    assert snap["available_kopecks"] == 0
    assert snap["paid_kopecks"] == 55000
    assert snap["payout_hold_kopecks"] == 0


def test_void_skips_hold_and_paid(db_session):
    user = _user(db_session, 64)
    payer = _user(db_session, 65, created_at=datetime.utcnow())
    svc = RevenueShareService(db_session)
    code = svc.ensure_code(user)
    db_session.commit()
    svc.apply_code(payer, code)
    db_session.commit()
    pay_id = "pay_payout_void"
    svc.accrue_subscription(
        payer_id=65,
        amount_rub=100,
        reference_id=payment_reference_id(pay_id),
    )
    db_session.commit()
    row = db_session.query(RevenueShareLedger).one()
    row.status = "paid"
    db_session.commit()
    assert svc.void_subscription_share(pay_id) == 0
    db_session.refresh(row)
    assert row.status == "paid"
    row.status = "payout_hold"
    db_session.commit()
    assert svc.void_subscription_share(pay_id) == 0
    db_session.refresh(row)
    assert row.status == "payout_hold"


def test_banned_user_cannot_cash_out(db_session):
    user = _user(db_session, 66)
    svc = RevenueShareService(db_session)
    _available_share(db_session, user, 20000, 301)
    user.banned_at = datetime.utcnow()
    db_session.commit()
    with pytest.raises(RevenueShareError):
        svc.convert_to_stars(user)


def test_snapshot_payout_fields(db_session):
    user = _user(db_session, 67)
    svc = RevenueShareService(db_session)
    snap = svc.snapshot(user)
    assert snap["payout_hold_kopecks"] == 0
    assert snap["paid_kopecks"] == 0
    assert snap["kopecks_per_star"] == KOPECKS_PER_STAR
    assert snap["min_card_kopecks"] == MIN_CARD_PAYOUT_KOPECKS
    assert snap["convertible_stars"] == 0
    assert snap["payouts"] == []
    assert snap["rules"]["min_card_kopecks"] == MIN_CARD_PAYOUT_KOPECKS
