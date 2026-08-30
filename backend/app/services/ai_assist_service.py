"""Короткий ассистент чата: переписать / ответить / сжать."""
from __future__ import annotations

import logging
from typing import Literal

from app.core.config import settings

logger = logging.getLogger(__name__)

AssistMode = Literal["rewrite", "reply", "summarize"]


def _local_assist(text: str, mode: AssistMode) -> str:
    clean = " ".join((text or "").split()).strip()
    if not clean:
        return ""
    if mode == "summarize":
        return clean if len(clean) <= 180 else f"{clean[:177].rstrip()}…"
    if mode == "reply":
        snippet = clean if len(clean) <= 80 else f"{clean[:77].rstrip()}…"
        return f"Ок, понял: {snippet}"
    if clean.endswith("!"):
        return clean
    return f"{clean[0].upper()}{clean[1:]}" if len(clean) > 1 else clean.upper()


def assist_text(text: str, mode: AssistMode, *, priority: bool) -> dict:
    source = (text or "").strip()
    if not source:
        return {"text": "", "result": "", "mode": mode, "priority": priority, "source": "empty"}
    if mode not in ("rewrite", "reply", "summarize"):
        mode = "rewrite"

    used = "local"
    result = _local_assist(source, mode)
    api_key = (settings.OPENAI_API_KEY or "").strip()
    if api_key:
        try:
            import openai

            client = openai.OpenAI(api_key=api_key, timeout=25 if priority else 12)
            prompts = {
                "rewrite": "Перепиши текст короче и яснее, сохрани смысл и язык. Только результат.",
                "reply": "Напиши короткий вежливый ответ на сообщение. Только текст ответа.",
                "summarize": "Сожми текст в 1–2 предложения. Только результат.",
            }
            retries = 3 if priority else 1
            last_error = None
            for _ in range(retries):
                try:
                    response = client.chat.completions.create(
                        model=settings.OPENAI_FOOD_SCAN_MODEL or "gpt-4o-mini",
                        messages=[
                            {"role": "system", "content": prompts[mode]},
                            {"role": "user", "content": source[:4000]},
                        ],
                        max_tokens=220 if priority else 140,
                        temperature=0.4,
                    )
                    content = (response.choices[0].message.content or "").strip()
                    if content:
                        result = content
                        used = "openai"
                    break
                except Exception as exc:  # noqa: BLE001
                    last_error = exc
            if used == "local" and last_error:
                logger.warning("AI assist fallback to local: %s", last_error)
        except Exception as exc:  # noqa: BLE001
            logger.warning("AI assist client init failed: %s", exc)

    return {
        "text": source,
        "result": result or source,
        "mode": mode,
        "priority": bool(priority),
        "source": used,
    }
