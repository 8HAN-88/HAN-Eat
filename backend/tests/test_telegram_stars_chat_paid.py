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
from app.models.paid_features import CreatorBalance, PaidMessageUnlock, StarGift, StarTransaction
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
        StarGift.__table__,
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
    msg = svc.send_star_gift(1, gift_id=gift.id, conversation_id=conv.id, message="hi")
    db_session.commit()
    assert msg.type == "gift"
    assert "🌹" in msg.content
    assert svc.star_balance(1) == 175
    assert svc.creator_balance(2).available_stars == 25


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
