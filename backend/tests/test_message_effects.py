"""Message send effects (confetti / hearts / …)."""
import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base
from app.models.conversation import Conversation, ConversationMember, Message
from app.models.user import User
from app.models.user_block import UserBlock
from app.services.chat_service import ChatService
from app.services.message_effect_service import normalize_effect_id


@pytest.fixture()
def db_session():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(
        bind=engine,
        tables=[
            User.__table__,
            Conversation.__table__,
            ConversationMember.__table__,
            Message.__table__,
            UserBlock.__table__,
        ],
    )
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def _setup_direct(db):
    for uid in (1, 2):
        db.add(
            User(
                id=uid,
                email=f"u{uid}@effect.test",
                password_hash="h",
                name=f"U{uid}",
            )
        )
    conv = Conversation(
        type="direct",
        direct_user_low_id=1,
        direct_user_high_id=2,
    )
    db.add(conv)
    db.flush()
    for uid in (1, 2):
        db.add(ConversationMember(conversation_id=conv.id, user_id=uid))
    db.commit()
    return conv


def test_normalize_effect_whitelist():
    assert normalize_effect_id("Confetti") == "confetti"
    assert normalize_effect_id("") is None
    assert normalize_effect_id(None) is None
    with pytest.raises(ValueError, match="effect_id_invalid"):
        normalize_effect_id("laser_unicorn")


def test_send_text_with_effect(db_session):
    conv = _setup_direct(db_session)
    svc = ChatService(db_session)
    msg, is_new = svc.send_message(
        conversation_id=conv.id,
        sender_id=1,
        msg_type="text",
        content="🎉",
        effect_id="hearts",
    )
    assert is_new is True
    assert msg.effect_id == "hearts"


def test_send_rejects_unknown_effect(db_session):
    conv = _setup_direct(db_session)
    svc = ChatService(db_session)
    with pytest.raises(ValueError, match="effect_id_invalid"):
        svc.send_message(
            conversation_id=conv.id,
            sender_id=1,
            msg_type="text",
            content="nope",
            effect_id="unknown_fx",
        )
