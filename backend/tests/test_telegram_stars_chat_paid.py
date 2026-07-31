"""Tests for Telegram Stars chat paid features: paid media unlock, gifts, DM fee."""
import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

# Ensure sqlite before app.core.database import side effects in other modules.
import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

from app.core.database import Base
from app.models.conversation import Conversation, ConversationMember, Message
from app.models.notification import Notification
from app.models.paid_features import (
    CreatorBalance,
    CreatorPayoutRequest,
    PaidMessageException,
    PaidMessageUnlock,
    StarGift,
    StarTransaction,
)
from app.models.user import User
from app.services.paid_features_service import PaidFeaturesService


@pytest.fixture()
def db_session():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    tables = [
        User.__table__,
        Conversation.__table__,
        ConversationMember.__table__,
        Message.__table__,
        StarTransaction.__table__,
        CreatorBalance.__table__,
        PaidMessageUnlock.__table__,
        PaidMessageException.__table__,
        StarGift.__table__,
        Notification.__table__,
        CreatorPayoutRequest.__table__,
    ]
    Base.metadata.create_all(bind=engine, tables=tables)
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def _user(db, user_id: int, *, paid_message_stars: int = 0) -> User:
    u = User(
        id=user_id,
        email=f"u{user_id}@t.test",
        password_hash="h",
        name=f"U{user_id}",
        paid_message_stars=paid_message_stars,
    )
    db.add(u)
    db.flush()
    return u


def _credit(db, user_id: int, stars: int) -> None:
    db.add(
        StarTransaction(
            user_id=user_id,
            amount=stars,
            type="admin_adjust",
            status="completed",
        )
    )
    db.flush()


def test_purchase_paid_media_message(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    _credit(db_session, 2, 100)
    conv = Conversation(type="direct", direct_user_low_id=1, direct_user_high_id=2)
    db_session.add(conv)
    db_session.flush()
    db_session.add(ConversationMember(conversation_id=conv.id, user_id=1))
    db_session.add(ConversationMember(conversation_id=conv.id, user_id=2))
    msg = Message(
        conversation_id=conv.id,
        sender_id=1,
        type="image",
        content="",
        media_url="https://example.com/a.jpg",
        is_paid=True,
        price_stars=40,
    )
    db_session.add(msg)
    db_session.commit()

    svc = PaidFeaturesService(db_session)
    assert not svc.has_unlocked_message(2, msg)
    unlock = svc.purchase_message(2, msg.id)
    db_session.commit()
    assert unlock.amount_stars == 40
    assert svc.has_unlocked_message(2, msg)
    assert svc.star_balance(2) == 60
    assert svc.creator_balance(1).available_stars == 40


def test_charge_paid_message_fee(db_session):
    _user(db_session, 1, paid_message_stars=15)
    _user(db_session, 2)
    _credit(db_session, 2, 50)
    db_session.commit()
    svc = PaidFeaturesService(db_session)
    tx = svc.charge_paid_message_fee(2, 1, conversation_id=7, message_id=99)
    db_session.commit()
    assert tx is not None
    assert svc.star_balance(2) == 35
    assert svc.creator_balance(1).available_stars == 15


def test_paid_message_exception_skips_fee(db_session):
    _user(db_session, 1, paid_message_stars=20)
    _user(db_session, 2)
    _credit(db_session, 2, 50)
    db_session.commit()
    svc = PaidFeaturesService(db_session)
    svc.add_paid_message_exception(1, 2)
    db_session.commit()

    tx = svc.charge_paid_message_fee(2, 1, conversation_id=7, message_id=101)
    db_session.commit()
    assert tx is None
    assert svc.star_balance(2) == 50

    listed = svc.list_paid_message_exceptions(1)
    assert [u.id for u in listed] == [2]

    svc.remove_paid_message_exception(1, 2)
    db_session.commit()
    tx2 = svc.charge_paid_message_fee(2, 1, conversation_id=7, message_id=102)
    db_session.commit()
    assert tx2 is not None
    assert svc.star_balance(2) == 30


def test_spend_topup_does_not_wipe_creator_available(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    _credit(db_session, 1, 100)  # top-up
    svc = PaidFeaturesService(db_session)
    bal = svc.creator_balance(1)
    bal.available_stars = 40  # earnings ledger
    db_session.commit()

    svc._spend_stars(
        1,
        70,
        tx_type="donation",
        reference_type="user",
        reference_id=2,
        counterparty_user_id=2,
    )
    db_session.commit()
    assert svc.star_balance(1) == 30
    # Available earnings stay until spendable falls below them.
    assert svc.creator_balance(1).available_stars == 30


def test_payout_escrows_spendable_stars(db_session):
    _user(db_session, 1)
    _credit(db_session, 1, 200)
    svc = PaidFeaturesService(db_session)
    bal = svc.creator_balance(1)
    bal.available_stars = 80
    db_session.commit()

    payout = svc.request_creator_payout(1, 50)
    db_session.commit()
    assert payout.status == "pending"
    assert svc.star_balance(1) == 150
    assert svc.creator_balance(1).available_stars == 30
    assert svc.creator_balance(1).pending_stars == 50

    # Cannot spend escrowed amount while pending.
    assert svc.star_balance(1) == 150

    rejected = svc.review_payout(payout.id, reviewer_user_id=1, approve=False)
    db_session.commit()
    assert rejected.status == "rejected"
    assert svc.star_balance(1) == 200
    assert svc.creator_balance(1).available_stars == 80
    assert svc.creator_balance(1).pending_stars == 0

    payout2 = svc.request_creator_payout(1, 40)
    db_session.commit()
    approved = svc.review_payout(payout2.id, reviewer_user_id=1, approve=True)
    db_session.commit()
    assert approved.status == "paid"
    assert svc.star_balance(1) == 160
    assert svc.creator_balance(1).available_stars == 40
    assert svc.creator_balance(1).paid_out_stars == 40


def test_charge_paid_message_fee_once_per_album(db_session):
    _user(db_session, 1, paid_message_stars=10)
    _user(db_session, 2)
    _credit(db_session, 2, 100)
    db_session.commit()
    svc = PaidFeaturesService(db_session)
    first = svc.charge_paid_message_fee(
        2,
        1,
        conversation_id=7,
        message_id=1,
        media_group_id="album-abc",
    )
    second = svc.charge_paid_message_fee(
        2,
        1,
        conversation_id=7,
        message_id=2,
        media_group_id="album-abc",
    )
    db_session.commit()
    assert first is not None
    assert second is not None
    assert first.id == second.id
    assert svc.star_balance(2) == 90
    assert svc.creator_balance(1).available_stars == 10


def test_send_star_gift_direct(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    _credit(db_session, 1, 200)
    db_session.add(
        StarGift(
            slug="rose",
            title="Роза",
            emoji="🌹",
            stars=25,
            is_active=True,
            sort_order=1,
        )
    )
    conv = Conversation(type="direct", direct_user_low_id=1, direct_user_high_id=2)
    db_session.add(conv)
    db_session.flush()
    db_session.add(ConversationMember(conversation_id=conv.id, user_id=1))
    db_session.add(ConversationMember(conversation_id=conv.id, user_id=2))
    db_session.commit()

    svc = PaidFeaturesService(db_session)
    gift = svc.list_star_gifts()[0]
    msg = svc.send_star_gift(
        1,
        gift_id=gift.id,
        conversation_id=conv.id,
        message="hi",
        idempotency_key="gift-once",
    )
    again = svc.send_star_gift(
        1,
        gift_id=gift.id,
        conversation_id=conv.id,
        message="hi",
        idempotency_key="gift-once",
    )
    db_session.commit()
    assert msg.type == "gift"
    assert again.id == msg.id
    assert "🌹" in msg.content
    assert svc.star_balance(1) == 175
    assert svc.creator_balance(2).available_stars == 25


def test_pay_for_reaction_idempotent(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    _credit(db_session, 2, 50)
    conv = Conversation(type="direct", direct_user_low_id=1, direct_user_high_id=2)
    db_session.add(conv)
    db_session.flush()
    msg = Message(
        conversation_id=conv.id,
        sender_id=1,
        type="text",
        content="hi",
    )
    db_session.add(msg)
    db_session.commit()

    svc = PaidFeaturesService(db_session)
    svc.pay_for_reaction(
        2, message=msg, amount_stars=10, idempotency_key="react-1"
    )
    svc.pay_for_reaction(
        2, message=msg, amount_stars=10, idempotency_key="react-1"
    )
    db_session.commit()
    assert svc.star_balance(2) == 40
    assert svc.creator_balance(1).available_stars == 10


def test_purchase_requires_membership(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    _credit(db_session, 2, 100)
    conv = Conversation(type="direct", direct_user_low_id=1, direct_user_high_id=3)
    db_session.add(conv)
    db_session.flush()
    msg = Message(
        conversation_id=conv.id,
        sender_id=1,
        type="image",
        content="",
        media_url="x",
        is_paid=True,
        price_stars=10,
    )
    db_session.add(msg)
    db_session.commit()
    svc = PaidFeaturesService(db_session)
    with pytest.raises(HTTPException) as exc:
        svc.purchase_message(2, msg.id)
    assert exc.value.status_code == 403


def test_forward_paid_media_requires_unlock(db_session):
    from app.services.chat_service import ChatService

    _user(db_session, 1)
    _user(db_session, 2)
    _credit(db_session, 2, 100)
    src = Conversation(type="direct", direct_user_low_id=1, direct_user_high_id=2)
    db_session.add(src)
    db_session.flush()
    dst = Conversation(type="group", title="g")
    db_session.add(dst)
    db_session.flush()
    for cid, uid in ((src.id, 1), (src.id, 2), (dst.id, 1), (dst.id, 2)):
        db_session.add(ConversationMember(conversation_id=cid, user_id=uid))
    msg = Message(
        conversation_id=src.id,
        sender_id=1,
        type="image",
        content="",
        media_url="https://example.com/paid.jpg",
        is_paid=True,
        price_stars=20,
    )
    db_session.add(msg)
    db_session.commit()

    chat = ChatService(db_session)
    with pytest.raises(ValueError, match="paid_media_locked"):
        chat.forward_message(
            target_conversation_id=dst.id,
            source_conversation_id=src.id,
            message_id=msg.id,
            sender_id=2,
        )

    PaidFeaturesService(db_session).purchase_message(2, msg.id)
    db_session.commit()
    forwarded = chat.forward_message(
        target_conversation_id=dst.id,
        source_conversation_id=src.id,
        message_id=msg.id,
        sender_id=2,
    )
    db_session.commit()
    assert forwarded.is_paid is True
    assert int(forwarded.price_stars or 0) == 20
    assert forwarded.media_url == "https://example.com/paid.jpg"
    assert forwarded.media_group_id == msg.media_group_id
