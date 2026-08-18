"""Voice/video-note transcription (Telegram Premium voice-to-text)."""
from __future__ import annotations

import os
import re
from typing import Optional
from urllib.parse import unquote, urlparse

from app.core.config import settings


class TranscriptionUnavailable(Exception):
    pass


def _local_upload_path(media_url: str) -> Optional[str]:
    raw = unquote((media_url or "").strip())
    if not raw:
        return None
    marker = "/uploads/"
    if marker in raw:
        key = "uploads/" + raw.split(marker, 1)[1].split("?", 1)[0]
    elif raw.startswith("uploads/"):
        key = raw.split("?", 1)[0]
    else:
        path = urlparse(raw).path.lstrip("/")
        if path.startswith("uploads/"):
            key = path
        else:
            return None
    full = os.path.join(os.getcwd(), key)
    if os.path.isfile(full):
        return full
    return None


def load_media_bytes(media_url: str) -> bytes:
    local = _local_upload_path(media_url)
    if local:
        with open(local, "rb") as handle:
            return handle.read()
    url = (media_url or "").strip()
    if not re.match(r"^https?://", url):
        raise TranscriptionUnavailable()
    try:
        import httpx

        response = httpx.get(url, timeout=20.0, follow_redirects=True)
        response.raise_for_status()
        return response.content
    except Exception as exc:
        raise TranscriptionUnavailable() from exc


def transcribe_audio_bytes(data: bytes, filename: str = "voice.ogg") -> str:
    if not data:
        raise TranscriptionUnavailable()
    key = (getattr(settings, "OPENAI_API_KEY", None) or "").strip()
    if not key:
        if os.environ.get("HAN_STT_STUB") == "1":
            return "Распознанный текст"
        raise TranscriptionUnavailable()
    import openai

    client = openai.OpenAI(api_key=key)
    result = client.audio.transcriptions.create(
        model="whisper-1",
        file=(filename, data),
    )
    text = (getattr(result, "text", None) or "").strip()
    if not text:
        raise TranscriptionUnavailable()
    return text[:4000]
