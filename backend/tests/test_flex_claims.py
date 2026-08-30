from datetime import datetime, timedelta

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base
from app.models.flex_subscription import (
    SubscriptionFeature,
    SubscriptionFeatureBlock,
    UserFlexSlot,
    UserFlexSubscription,
)
from app.models.post_reaction import PostReaction
from app.models.subscription import Subscription
from app.models.support_ticket import SupportTicket
from app.models.user import User
from app.services.flex_subscription_service import FlexSubscriptionService


@pytest.fixture()
def db_session():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    tables = [
        User.__table__,
        Subscription.__table__,
        SubscriptionFeatureBlock.__table__,
        SubscriptionFeature.__table__,
        UserFlexSubscription.__table__,
        UserFlexSlot.__table__,
        PostReaction.__table__,
        SupportTicket.__table__,
    ]
    Base.metadata.create_all(bind=engine, tables=tables)
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def _user(db, user_id: int = 1) -> User:
    u = User(
        id=user_id,
        email=f"u{user_id}@t.test",
        password_hash="h",
        name=f"U{user_id}",
    )
    db.add(u)
    db.commit()
    return u


def test_exclusive_reactions_follow_flex_level(db_session):
    from app.services.subscription_service import SubscriptionService

    _user(db_session)
    sub = SubscriptionService(db_session)
    assert not sub.has_entitlement(1, "exclusive_reactions")
    FlexSubscriptionService(db_session).activate(1, 3)
    db_session.commit()
    assert sub.has_entitlement(1, "exclusive_reactions")


def test_post_reaction_summary(db_session):
    from app.services.post_reaction_service import summarize_post_reactions

    _user(db_session)
    db_session.add(PostReaction(post_id=9, user_id=1, emoji="👍"))
    db_session.commit()
    out = summarize_post_reactions(db_session, [9], 1)
    assert out[9][0]["emoji"] == "👍"
    assert out[9][0]["reacted_by_me"] is True


def test_ai_assist_priority_flag():
    from app.services.ai_assist_service import assist_text

    out = assist_text("привет из чата", "rewrite", priority=True)
    assert out["priority"] is True
    assert out["result"]
    local = assist_text("короткий текст для ответа", "reply", priority=False)
    assert local["mode"] == "reply"
    assert local["result"]


def test_support_priority_queue_ahead_of_regular(db_session):
    from app.api.v1.support import _ticket_queue_position

    _user(db_session, 1)
    _user(db_session, 2)
    regular = SupportTicket(
        user_id=1,
        type="other",
        subject="a",
        message="m",
        status="open",
        is_priority=False,
        created_at=datetime.utcnow() - timedelta(minutes=10),
    )
    priority = SupportTicket(
        user_id=2,
        type="other",
        subject="b",
        message="m",
        status="open",
        is_priority=True,
        created_at=datetime.utcnow(),
    )
    db_session.add_all([regular, priority])
    db_session.commit()
    assert _ticket_queue_position(db_session, priority) == 1
    assert _ticket_queue_position(db_session, regular) == 2
