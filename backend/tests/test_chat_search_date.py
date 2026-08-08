"""Date filter for chat message search."""
import os
from datetime import datetime, timedelta

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base
from app.models.conversation import (
    Conversation,
    ConversationMember,
    Message,
    MessageHide,
)
from app.models.user import User
from app.models.user_block import UserBlock
from app.services.chat_service import ChatService


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
            MessageHide.__table__,
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


def _seed(db):
    for uid, name in ((1, "A"), (2, "B")):
        db.add(
            User(
                id=uid,
                email=f"{name.lower()}@test.com",
                name=name,
                password_hash="x",
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
    day = datetime(2026, 8, 8, 10, 0, 0)
    db.add_all(
        [
            Message(
                conversation_id=conv.id,
                sender_id=1,
                type="text",
                content="hello alpha",
                created_at=day,
            ),
            Message(
                conversation_id=conv.id,
                sender_id=2,
                type="text",
                content="hello beta",
                created_at=day + timedelta(days=1),
            ),
            Message(
                conversation_id=conv.id,
                sender_id=1,
                type="text",
                content="other",
                created_at=day,
            ),
        ]
    )
    db.commit()
    return conv.id, day


def test_search_messages_filters_by_date(db_session, monkeypatch):
    conv_id, day = _seed(db_session)
    svc = ChatService(db_session)
    monkeypatch.setattr(svc, "get_conversation_row", lambda *a, **k: None)
    hits = svc.search_messages(
        1,
        "hello",
        conversation_id=conv_id,
        date_from=day.replace(hour=0, minute=0, second=0),
        date_to=day.replace(hour=23, minute=59, second=59),
    )
    ids = [h["message"].id for h in hits]
    assert len(ids) == 1
    assert hits[0]["message"].content == "hello alpha"


def test_search_messages_date_only_without_query(db_session, monkeypatch):
    conv_id, day = _seed(db_session)
    svc = ChatService(db_session)
    monkeypatch.setattr(svc, "get_conversation_row", lambda *a, **k: None)
    hits = svc.search_messages(
        1,
        "",
        conversation_id=conv_id,
        date_from=day.replace(hour=0, minute=0, second=0),
        date_to=day.replace(hour=23, minute=59, second=59),
    )
    texts = sorted(h["message"].content for h in hits)
    assert texts == ["hello alpha", "other"]
