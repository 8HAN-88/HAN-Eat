"""Inbox preview follows the newest message that is still in the chat."""
import os
from datetime import datetime

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base
from app.models.conversation import Conversation, ConversationMember, Message
from app.models.user import User
from app.services.chat_service import ChatService, edit_changes_inbox_preview


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
        ],
    )
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def test_edit_changes_inbox_preview_only_for_the_latest_message():
    assert edit_changes_inbox_preview(4, 4) is True
    assert edit_changes_inbox_preview(3, 4) is False
    assert edit_changes_inbox_preview(4, None) is False


def test_deleted_newer_message_is_not_the_inbox_tail(db_session):
    db_session.add(
        User(id=1, email="a@test.com", name="A", password_hash="x")
    )
    conv = Conversation(type="direct", direct_user_low_id=1, direct_user_high_id=2)
    db_session.add(conv)
    db_session.flush()
    older = Message(
        conversation_id=conv.id,
        sender_id=1,
        type="text",
        content="older",
        created_at=datetime(2026, 8, 1, 10, 0, 0),
    )
    newer = Message(
        conversation_id=conv.id,
        sender_id=1,
        type="text",
        content="newer",
        created_at=datetime(2026, 8, 1, 11, 0, 0),
        deleted_at=datetime(2026, 8, 1, 12, 0, 0),
    )
    db_session.add_all([older, newer])
    db_session.commit()

    svc = ChatService(db_session)
    latest = svc.latest_visible_message_id(conv.id)
    assert latest == older.id
    assert edit_changes_inbox_preview(older.id, latest) is True
    assert edit_changes_inbox_preview(newer.id, latest) is False
