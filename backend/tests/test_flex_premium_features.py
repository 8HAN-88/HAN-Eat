import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest

from app.services.chat_checklist_service import (
    build_checklist_content,
    checklist_preview_text,
    parse_checklist,
    toggle_checklist_item,
)
from app.services.profile_style import (
    normalize_emoji_status,
    normalize_profile_color,
    profile_color_hex,
)
from app.services.voice_transcription_service import (
    TranscriptionUnavailable,
    transcribe_audio_bytes,
)


def test_build_and_toggle_checklist():
    content = build_checklist_content("Покупки", ["Хлеб", "Молоко"])
    parsed = parse_checklist(content)
    assert parsed is not None
    assert parsed["title"] == "Покупки"
    assert len(parsed["items"]) == 2
    assert parsed["items"][0]["done"] is False
    updated = toggle_checklist_item(content, 0, True)
    again = parse_checklist(updated)
    assert again["items"][0]["done"] is True
    assert again["items"][1]["done"] is False
    assert checklist_preview_text(updated) == "☑ Покупки (1/2)"


def test_checklist_rejects_empty_title():
    with pytest.raises(ValueError, match="checklist_title_required"):
        build_checklist_content("  ", ["Один"])


def test_normalize_profile_color():
    assert normalize_profile_color("Blue") == "blue"
    assert profile_color_hex("pink") == "#D81B60"
    assert normalize_profile_color("") is None
    with pytest.raises(ValueError, match="bad_profile_color"):
        normalize_profile_color("gold")


def test_normalize_emoji_status():
    assert normalize_emoji_status(" 🔥 ") == "🔥"
    assert normalize_emoji_status("") is None
    assert len(normalize_emoji_status("abcdefghij") or "") == 8
    assert normalize_emoji_status("[[e:42]]") == "ce:42"
    assert normalize_emoji_status("ce:7") == "ce:7"


def test_stt_stub(monkeypatch):
    monkeypatch.setattr(
        "app.services.voice_transcription_service.settings.OPENAI_API_KEY",
        "",
    )
    monkeypatch.setenv("HAN_STT_STUB", "1")
    assert transcribe_audio_bytes(b"fake-audio") == "Распознанный текст"
    monkeypatch.delenv("HAN_STT_STUB", raising=False)
    with pytest.raises(TranscriptionUnavailable):
        transcribe_audio_bytes(b"fake-audio")
