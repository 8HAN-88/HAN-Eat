"""BotFather username rules and helpers."""

import pytest
from fastapi import HTTPException

from app.api.v1 import bots as b


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("Weather_Bot", "weather_bot"),
        ("@DemoBot", "demobot"),
        ("a_bot", "a_bot"),
        ("my_shop_bot", "my_shop_bot"),
    ],
)
def test_normalize_bot_username_ok(raw, expected):
    assert b._normalize_bot_username(raw) == expected


@pytest.mark.parametrize(
    "raw",
    [
        "bot",  # too short / doesn't start properly enough for 5 chars ending bot: "bot"=3
        "ab",  # too short
        "weather",  # must end with bot
        "1weather_bot",  # must start with letter
        "bad-name_bot",  # hyphen not allowed
        "x" * 30 + "_bot",  # too long (>32)
    ],
)
def test_normalize_bot_username_rejects(raw):
    with pytest.raises(HTTPException) as exc:
        b._normalize_bot_username(raw)
    assert exc.value.status_code == 400


def test_normalize_accepts_five_char_minimum():
    assert b._normalize_bot_username("a_bot") == "a_bot"
