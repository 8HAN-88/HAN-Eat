"""Reply quotes stay readable when the original message is not on the page."""
import os
from datetime import datetime

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
from app.services.chat_reply_preview import reply_preview_text
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
        ],
    )
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def test_reply_preview_text_labels_media_and_trims_text():
    assert reply_preview_text("voice", "12") == "Голосовое сообщение"
    assert reply_preview_text("image", "caption") == "Фото"
    assert reply_preview_text("text", "  hello\nthere  ") == "hello there"
    assert reply_preview_text("text", "x" * 200) == "x" * 120
    assert reply_preview_text("text", "secret", deleted=True) == "Сообщение удалено"
    assert reply_preview_text("file", "notes.pdf") == "notes.pdf"
    assert reply_preview_text("text", "👤 Контакт\nАнна") == "Контакт"


def test_reply_snippet_uses_the_original_and_hides_deleted(db_session):
    db_session.add_all(
        [
            User(id=1, email="a@test.com", name="Ann", password_hash="x"),
            User(id=2, email="b@test.com", name="Bob", password_hash="x"),
        ]
    )
    conv = Conversation(type="direct", direct_user_low_id=1, direct_user_high_id=2)
    other = Conversation(type="group", title="Other")
    db_session.add_all([conv, other])
    db_session.flush()
    original = Message(
        conversation_id=conv.id,
        sender_id=2,
        type="text",
        content="встреча в семь",
        created_at=datetime(2026, 11, 1, 10, 0, 0),
    )
    deleted = Message(
        conversation_id=conv.id,
        sender_id=2,
        type="text",
        content="секрет",
        created_at=datetime(2026, 11, 1, 11, 0, 0),
        deleted_at=datetime(2026, 11, 1, 12, 0, 0),
    )
    foreign = Message(
        conversation_id=other.id,
        sender_id=2,
        type="text",
        content="чужой текст",
        created_at=datetime(2026, 11, 1, 9, 0, 0),
    )
    db_session.add_all([original, deleted, foreign])
    db_session.commit()

    snippets = ChatService(db_session).reply_snippets(
        conv.id,
        [original.id, deleted.id, foreign.id, 999999],
        1,
    )
    assert snippets[original.id]["preview"] == "встреча в семь"
    assert snippets[original.id]["sender_name"] == "Bob"
    assert snippets[original.id]["is_mine"] is False
    assert snippets[original.id]["deleted"] is False
    assert snippets[deleted.id]["preview"] == "Сообщение удалено"
    assert snippets[deleted.id]["deleted"] is True
    assert snippets[deleted.id]["sender_name"] is None
    assert snippets[foreign.id]["preview"] == "Сообщение"
    assert "чужой" not in snippets[foreign.id]["preview"]
    assert snippets[999999]["preview"] == "Сообщение"
