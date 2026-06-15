"""Tests for chat poll service."""
import json

import pytest

from app.services.chat_poll_service import (
    build_poll_content,
    close_message_poll,
    parse_poll_content,
    poll_preview_text,
)


class _EmptyQuery:
    def filter(self, *_args, **_kwargs):
        return self

    def group_by(self, *_args, **_kwargs):
        return self

    def all(self):
        return []


class _MsgQuery:
    def __init__(self, msg):
        self._msg = msg

    def filter(self, *_args, **_kwargs):
        return self

    def first(self):
        return self._msg


class _Db:
    def __init__(self, msg):
        self.msg = msg

    def query(self, *args):
        if len(args) == 1:
            from app.models.conversation import Message

            if args[0] is Message:
                return _MsgQuery(self.msg)
        return _EmptyQuery()

    def flush(self):
        pass


def test_build_poll_content_minimal():
    raw = build_poll_content("Куда идём?", ["Домой", "В кафе"])
    data = json.loads(raw)
    assert data["poll"]["question"] == "Куда идём?"
    assert len(data["poll"]["options"]) == 2
    assert data["poll"]["settings"]["show_voter_names"] is True


def test_build_poll_content_with_settings():
    raw = build_poll_content(
        "Обед?",
        ["Пицца", "Суши"],
        description="Выберите одно",
        settings={"multiple_choice": True, "time_limit_enabled": True, "duration_hours": 8},
    )
    data = json.loads(raw)
    assert data["poll"]["description"] == "Выберите одно"
    assert data["poll"]["settings"]["multiple_choice"] is True
    assert data["poll"]["closes_at"] is not None


def test_build_poll_content_rejects_single_option():
    with pytest.raises(ValueError, match="poll_options_required"):
        build_poll_content("Q?", ["only one"])


def test_poll_preview_text():
    raw = build_poll_content("Где ужинаем?", ["Дома", "Вне"])
    assert poll_preview_text(raw) == "📊 Где ужинаем?"


def test_parse_poll_content_invalid():
    assert parse_poll_content("not json") is None


def test_close_message_poll_marks_closed():
    class _Msg:
        type = "poll"
        id = 5
        sender_id = 7
        content = build_poll_content("Q?", ["A", "B"])

    msg = _Msg()
    db = _Db(msg)
    result = close_message_poll(db, 5, 7)
    data = json.loads(result)
    assert data["poll"]["is_closed"] is True


def test_close_message_poll_forbidden_for_non_author():
    class _Msg:
        type = "poll"
        id = 5
        sender_id = 99
        content = build_poll_content("Q?", ["A", "B"])

    with pytest.raises(ValueError, match="forbidden"):
        close_message_poll(_Db(_Msg()), 5, 7)


def test_close_message_poll_already_closed():
    class _Msg:
        type = "poll"
        id = 5
        sender_id = 7
        content = build_poll_content("Q?", ["A", "B"])

    msg = _Msg()
    data = json.loads(msg.content)
    data["poll"]["is_closed"] = True
    msg.content = json.dumps(data)

    with pytest.raises(ValueError, match="poll_already_closed"):
        close_message_poll(_Db(msg), 5, 7)
