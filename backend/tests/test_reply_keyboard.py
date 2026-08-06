"""Bot ReplyKeyboard normalize + member state."""
import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base
from app.models.conversation import Conversation, ConversationMember
from app.models.user import User
from app.services import reply_keyboard_service as rks


@pytest.fixture()
def db_session():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(
        bind=engine,
        tables=[User.__table__, Conversation.__table__, ConversationMember.__table__],
    )
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def test_normalize_reply_keyboard_rows():
    raw = [[{"text": "Да"}, {"text": "Нет"}], [{"text": "Позже"}]]
    assert rks.normalize_reply_keyboard(raw) == [
        [{"text": "Да"}, {"text": "Нет"}],
        [{"text": "Позже"}],
    ]
    assert rks.normalize_reply_keyboard([]) is None
    assert rks.normalize_reply_keyboard("not-json") is None


def test_set_and_clear_member_keyboard(db_session):
    u = User(id=1, email="a@t.test", password_hash="h", name="A")
    bot = User(id=2, email="b@t.test", password_hash="h", name="Bot", is_bot=True)
    db_session.add_all([u, bot])
    conv = Conversation(id=10, type="direct", direct_user_low_id=1, direct_user_high_id=2)
    db_session.add(conv)
    m = ConversationMember(conversation_id=10, user_id=1)
    db_session.add(m)
    db_session.commit()

    kb = [[{"text": "Ок"}]]
    rks.set_member_reply_keyboard(
        db_session,
        conversation_id=10,
        user_id=1,
        keyboard=kb,
        one_time=True,
        placeholder="Выберите",
    )
    db_session.commit()
    db_session.refresh(m)
    payload = rks.keyboard_payload_from_member(m)
    assert payload["reply_keyboard"] == kb
    assert payload["reply_keyboard_one_time"] is True
    assert payload["reply_keyboard_placeholder"] == "Выберите"

    assert rks.clear_one_time_if_needed(
        db_session, conversation_id=10, user_id=1
    )
    db_session.commit()
    db_session.refresh(m)
    assert m.reply_keyboard_json is None
    assert m.reply_keyboard_one_time is False


def test_does_not_set_on_bot_member(db_session):
    bot = User(id=2, email="bot@t.test", password_hash="h", name="Bot", is_bot=True)
    db_session.add(bot)
    conv = Conversation(id=11, type="direct")
    db_session.add(conv)
    m = ConversationMember(conversation_id=11, user_id=2)
    db_session.add(m)
    db_session.commit()
    rks.set_member_reply_keyboard(
        db_session,
        conversation_id=11,
        user_id=2,
        keyboard=[[{"text": "X"}]],
    )
    db_session.commit()
    db_session.refresh(m)
    assert m.reply_keyboard_json is None
