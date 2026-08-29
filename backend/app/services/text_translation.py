"""
Перевод текстов (чат / legacy). Вынесено из kitchen recipes router.
"""
from __future__ import annotations

import hashlib
import logging
import random
import time
from typing import Dict, List, Optional

from app.core.redis_client import redis_client

logger = logging.getLogger(__name__)

TRANSLATOR_AVAILABLE = False
GoogleTranslator = None
Translator = None

try:
    from deep_translator import GoogleTranslator as _GoogleTranslator

    GoogleTranslator = _GoogleTranslator
    TRANSLATOR_AVAILABLE = True
    logger.info("deep-translator доступен для переводов")
except ImportError:
    try:
        from googletrans import Translator as _Translator

        TRANSLATOR_AVAILABLE = True
        Translator = _Translator()
        logger.info("googletrans доступен для переводов")
    except (ImportError, AttributeError) as e:
        logger.warning("Переводчик не установлен: %s", e)
        TRANSLATOR_AVAILABLE = False


def get_cached_translation(text: str, target_lang: str) -> Optional[str]:
    if not text or target_lang == "en":
        return None
    try:
        cache_key = (
            f"translation:{hashlib.md5(f'{text}:{target_lang}'.encode()).hexdigest()}"
        )
        cached = redis_client.get(cache_key)
        if cached:
            return cached.decode("utf-8")
    except Exception as e:
        logger.warning("Redis translation cache read error: %s", e)
    return None


def cache_translation(text: str, target_lang: str, translated: str) -> None:
    if not text or not translated or target_lang == "en":
        return
    try:
        cache_key = (
            f"translation:{hashlib.md5(f'{text}:{target_lang}'.encode()).hexdigest()}"
        )
        redis_client.setex(cache_key, 86400 * 30, translated)
    except Exception as e:
        logger.warning("Redis translation cache write error: %s", e)


def translate_text(
    text: str,
    target_lang: str,
    max_retries: int = 3,
    *,
    priority: bool = False,
) -> str:
    if not text or not target_lang or target_lang == "en":
        return text
    if not TRANSLATOR_AVAILABLE:
        return text

    cached = get_cached_translation(text, target_lang)
    if cached:
        return cached

    translated = text
    for attempt in range(max_retries):
        try:
            if GoogleTranslator is not None:
                translator = GoogleTranslator(source="auto", target=target_lang)
                if len(text) > 500:
                    sentences = text.split(". ")
                    translated_sentences = []
                    for sentence in sentences:
                        if not sentence.strip():
                            continue
                        cached_sentence = get_cached_translation(
                            sentence.strip(), target_lang
                        )
                        if cached_sentence:
                            translated_sentences.append(cached_sentence)
                        else:
                            piece = translator.translate(sentence.strip())
                            cache_translation(sentence.strip(), target_lang, piece)
                            translated_sentences.append(piece)
                    translated = ". ".join(translated_sentences)
                else:
                    translated = translator.translate(text)
                break
            if Translator is not None:
                result = Translator.translate(text, dest=target_lang)
                translated = result.text
                break
        except Exception as e:
            error_str = str(e)
            is_connection_error = (
                "Connection aborted" in error_str
                or "ConnectionResetError" in error_str
                or "Connection refused" in error_str
                or "Failed to fetch" in error_str
                or "timeout" in error_str.lower()
            )
            if is_connection_error and attempt < max_retries - 1:
                wait_time = 0.15 if priority else (2**attempt) + random.uniform(0, 1)
                logger.warning(
                    "Translation connection error (attempt %s/%s), retrying in %.1fs...",
                    attempt + 1,
                    max_retries,
                    wait_time,
                )
                time.sleep(wait_time)
                continue
            if attempt == max_retries - 1:
                logger.warning(
                    "Translation error for '%s...' (after %s attempts): %s",
                    text[:30],
                    max_retries,
                    e,
                )
            else:
                logger.warning(
                    "Translation error for '%s...' (attempt %s/%s): %s",
                    text[:30],
                    attempt + 1,
                    max_retries,
                    e,
                )

    if translated and translated != text:
        cache_translation(text, target_lang, translated)
    return translated


def translate_list(items: List[str], target_lang: str) -> List[str]:
    if not items or not target_lang or target_lang == "en":
        return items
    return [translate_text(item, target_lang) for item in items]


def translate_steps(steps: List[Dict], target_lang: str) -> List[Dict]:
    if not steps or not target_lang or target_lang == "en":
        return steps
    translated = []
    for step in steps:
        step_text = step.get("step", "") or step.get("instruction", "")
        translated_text = translate_text(step_text, target_lang)
        translated.append(
            {
                "number": step.get("number", len(translated) + 1),
                "step": translated_text,
                "instruction": translated_text,
                "image": step.get("image"),
            }
        )
    return translated
