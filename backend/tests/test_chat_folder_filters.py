"""Chat folder filter normalization (contacts / non_contacts / bots)."""
import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

from app.services.chat_service import ChatService


def test_normalize_filters_contacts_flags():
    out = ChatService._normalize_filters(
        {
            "groups": 1,
            "contacts": True,
            "non_contacts": "yes",
            "bots": True,
            "direct": False,
            "exclude_bots": True,
            "unknown": True,
        }
    )
    assert out == {
        "groups": True,
        "channels": False,
        "direct": False,
        "contacts": True,
        "non_contacts": True,
        "bots": True,
        "unread_only": False,
        "exclude_muted": False,
        "exclude_archived": False,
        "exclude_bots": True,
    }


def test_normalize_filters_private_alias_and_empty():
    assert ChatService._normalize_filters(None) == {}
    assert ChatService._normalize_filters({}) == {}
    aliased = ChatService._normalize_filters({"private": True})
    assert aliased["direct"] is True
    assert aliased["contacts"] is False
    assert aliased["non_contacts"] is False
    assert aliased["bots"] is False
