import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base
from app.core.entitlements import EXCLUSIVE_CHAT_REACTIONS, FREE_CHAT_REACTIONS
from app.models.conversation import (
    Contact,
    Conversation,
    ConversationMember,
    Message,
    MessageHide,
    MessageReaction,
)
from app.models.flex_subscription import (
    SubscriptionFeature,
    SubscriptionFeatureBlock,
    UserFlexGift,
    UserFlexSlot,
    UserFlexSubscription,
)
from app.models.saved_tag import SavedMessageTag, SavedTag
from app.models.subscription import Subscription
from app.models.user import User
from app.models.user_block import UserBlock
from app.services.chat_service import ChatService
from app.services.flex_subscription_service import FlexSubscriptionService
from app.services.saved_tag_service import (
    SavedTagError,
    create_tag,
    set_message_tags,
    tags_by_message_ids,
)
from app.services.voice_privacy import can_send_voice_to, normalize_voice_privacy


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
            Subscription.__table__,
            SubscriptionFeatureBlock.__table__,
            SubscriptionFeature.__table__,
            UserFlexSubscription.__table__,
            UserFlexSlot.__table__,
            UserFlexGift.__table__,
            Conversation.__table__,
            ConversationMember.__table__,
            Message.__table__,
            MessageHide.__table__,
            MessageReaction.__table__,
            Contact.__table__,
            UserBlock.__table__,
            SavedTag.__table__,
            SavedMessageTag.__table__,
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
    u = User(
        id=user_id,
        email=f"u{user_id}@t.test",
        password_hash="h",
        name=f"U{user_id}",
        **kwargs,
    )
    db.add(u)
    db.commit()
    return u


def test_normalize_voice_privacy():
    assert normalize_voice_privacy("Everybody") == "everybody"
    assert normalize_voice_privacy("contacts") == "contacts"
    with pytest.raises(ValueError, match="invalid_voice_privacy"):
        normalize_voice_privacy("friends")


def test_can_send_voice_to_privacy(db_session):
    sender = _user(db_session, 1)
    recipient = _user(db_session, 2, voice_privacy="everybody")
    assert can_send_voice_to(db_session, sender.id, recipient) is True

    recipient.voice_privacy = "nobody"
    db_session.commit()
    assert can_send_voice_to(db_session, sender.id, recipient) is False
    assert can_send_voice_to(db_session, recipient.id, recipient) is True

    recipient.voice_privacy = "contacts"
    db_session.commit()
    assert can_send_voice_to(db_session, sender.id, recipient) is False
    db_session.add(Contact(owner_user_id=recipient.id, contact_user_id=sender.id))
    db_session.commit()
    assert can_send_voice_to(db_session, sender.id, recipient) is True


def test_free_and_exclusive_reaction_sets():
    assert "👍" in FREE_CHAT_REACTIONS
    assert "🔥" in EXCLUSIVE_CHAT_REACTIONS
    assert "👍" not in EXCLUSIVE_CHAT_REACTIONS


def test_any_emoji_reaction_requires_level(db_session):
    owner = _user(db_session, 1)
    peer = _user(db_session, 2)
    flex = FlexSubscriptionService(db_session)
    flex.ensure_catalog()
    flex.activate(1, 1)
    db_session.commit()

    chat = ChatService(db_session)
    conv = chat.get_or_create_direct(1, 2)
    msg = Message(conversation_id=conv.id, sender_id=owner.id, type="text", content="hi")
    db_session.add(msg)
    db_session.commit()

    chat.set_message_reaction(conv.id, msg.id, owner.id, "👍")
    with pytest.raises(ValueError, match="exclusive_reaction"):
        chat.set_message_reaction(conv.id, msg.id, owner.id, "🔥")
    with pytest.raises(ValueError, match="any_emoji_reaction"):
        chat.set_message_reaction(conv.id, msg.id, owner.id, "🐶")

    flex.activate(1, 36)
    db_session.commit()
    chat.set_message_reaction(conv.id, msg.id, owner.id, "🔥")
    with pytest.raises(ValueError, match="any_emoji_reaction"):
        chat.set_message_reaction(conv.id, msg.id, owner.id, "🐶")

    flex.activate(1, 40)
    db_session.commit()
    chat.set_message_reaction(conv.id, msg.id, owner.id, "🐶")
    assert peer.id > 0


def test_saved_tags_create_and_assign(db_session):
    user = _user(db_session, 1)
    chat = ChatService(db_session)
    saved = chat.get_or_create_saved(user.id)
    msg = Message(
        conversation_id=saved.id, sender_id=user.id, type="text", content="note"
    )
    db_session.add(msg)
    db_session.commit()

    tag = create_tag(db_session, user.id, "Работа", "💼")
    ids = set_message_tags(db_session, user.id, msg.id, [tag.id])
    db_session.commit()
    assert ids == [tag.id]
    mapped = tags_by_message_ids(db_session, user.id, [msg.id])
    assert mapped[msg.id] == [tag.id]

    rows, _ = chat.get_messages(saved.id, user.id, tag_id=tag.id)
    assert [row.id for row in rows] == [msg.id]

    with pytest.raises(SavedTagError, match="tag_title_required"):
        create_tag(db_session, user.id, "  ")


def test_archive_new_non_contact_chat(db_session):
    initiator = _user(db_session, 1)
    recipient = _user(db_session, 2, archive_non_contacts=True)
    flex = FlexSubscriptionService(db_session)
    flex.ensure_catalog()
    flex.activate(recipient.id, 40)
    db_session.commit()

    chat = ChatService(db_session)
    conv = chat.get_or_create_direct(initiator.id, recipient.id)
    db_session.commit()

    rec_member = (
        db_session.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conv.id,
            ConversationMember.user_id == recipient.id,
        )
        .first()
    )
    init_member = (
        db_session.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conv.id,
            ConversationMember.user_id == initiator.id,
        )
        .first()
    )
    assert rec_member.archived_at is not None
    assert rec_member.muted_at is not None
    assert init_member.archived_at is None
    assert init_member.muted_at is None


def test_archive_skips_contacts(db_session):
    initiator = _user(db_session, 1)
    recipient = _user(db_session, 2, archive_non_contacts=True)
    flex = FlexSubscriptionService(db_session)
    flex.ensure_catalog()
    flex.activate(recipient.id, 40)
    db_session.add(Contact(owner_user_id=recipient.id, contact_user_id=initiator.id))
    db_session.commit()

    chat = ChatService(db_session)
    conv = chat.get_or_create_direct(initiator.id, recipient.id)
    db_session.commit()
    rec_member = (
        db_session.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conv.id,
            ConversationMember.user_id == recipient.id,
        )
        .first()
    )
    assert rec_member.archived_at is None
