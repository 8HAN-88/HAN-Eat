"""Tests for chat poll service."""
import json

import pytest

from datetime import datetime, timedelta, timezone

from app.services.chat_poll_service import (
    apply_poll_expiry_to_message,
    build_poll_content,
    close_message_poll,
    parse_poll_content,
    poll_preview_text,
    poll_settings_need_premium,
    rebase_poll_closes_at,
    vote_on_message_poll,
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


def test_poll_settings_need_premium_simple_is_free():
    assert poll_settings_need_premium(None) is False
    assert poll_settings_need_premium({}) is False
    assert poll_settings_need_premium({"allow_change_vote": True}) is False


def test_poll_settings_need_premium_advanced():
    assert poll_settings_need_premium({"quiz_mode": True}) is True
    assert poll_settings_need_premium({"multiple_choice": True}) is True
    assert poll_settings_need_premium({"allow_add_options": True}) is True
    assert poll_settings_need_premium({"hide_results_until_closed": True}) is True
    assert poll_settings_need_premium({"time_limit_enabled": True}) is True
    assert poll_settings_need_premium({"random_order": True}) is True
    assert poll_settings_need_premium({"show_voter_names": False}) is True


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


def test_build_poll_quiz_requires_correct_option():
    with pytest.raises(ValueError, match="poll_quiz_correct_required"):
        build_poll_content(
            "Столица?",
            ["Париж", "Лондон"],
            settings={"quiz_mode": True, "correct_option_indices": []},
        )


def test_build_poll_quiz_forces_single_choice_and_correct():
    raw = build_poll_content(
        "Столица?",
        ["Париж", "Лондон"],
        settings={
            "quiz_mode": True,
            "correct_option_indices": [0],
            "multiple_choice": True,
            "allow_add_options": True,
            "allow_change_vote": True,
        },
    )
    settings = json.loads(raw)["poll"]["settings"]
    assert settings["quiz_mode"] is True
    assert settings["correct_option_indices"] == [0]
    assert settings["multiple_choice"] is False
    assert settings["allow_add_options"] is False
    assert settings["allow_change_vote"] is False


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


def test_apply_poll_expiry_to_message_closes_past_deadline():
    class _Msg:
        type = "poll"
        id = 9
        content = build_poll_content(
            "Q?",
            ["A", "B"],
            settings={"time_limit_enabled": True, "duration_hours": 1},
        )

    msg = _Msg()
    data = json.loads(msg.content)
    past = (datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(minutes=1)).isoformat()
    data["poll"]["closes_at"] = past
    msg.content = json.dumps(data)
    assert apply_poll_expiry_to_message(msg) is True
    assert json.loads(msg.content)["poll"]["is_closed"] is True


def test_vote_on_expired_poll_raises_closed():
    class _Msg:
        type = "poll"
        id = 11
        content = build_poll_content(
            "Q?",
            ["A", "B"],
            settings={"time_limit_enabled": True, "duration_hours": 1},
        )

    msg = _Msg()
    data = json.loads(msg.content)
    past = (datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(seconds=5)).isoformat()
    data["poll"]["closes_at"] = past
    msg.content = json.dumps(data)
    with pytest.raises(ValueError, match="poll_closed"):
        vote_on_message_poll(_Db(msg), 11, 3, 0)
    assert json.loads(msg.content)["poll"]["is_closed"] is True


def test_rebase_poll_closes_at_from_send_time():
    raw = build_poll_content(
        "Q?",
        ["A", "B"],
        settings={"time_limit_enabled": True, "duration_hours": 8},
    )
    send_at = datetime(2030, 1, 1, 12, 0, 0)
    rebased = rebase_poll_closes_at(raw, from_time=send_at)
    data = json.loads(rebased)
    closes = datetime.fromisoformat(data["poll"]["closes_at"])
    assert closes == send_at + timedelta(hours=8)
