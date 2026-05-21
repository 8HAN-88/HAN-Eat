"""
Пайплайн модерации: текст + эвристики, решение SAFE / WARNING / BLOCK.
"""
from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

from app.core.config import settings
from app.services.moderation_service import ModerationService

logger = logging.getLogger(__name__)

DECISION_SAFE = "safe"
DECISION_WARNING = "warning"
DECISION_BLOCK = "block"

# Пороги из ТЗ
TOXICITY_REVIEW = 0.4
TOXICITY_BLOCK = 0.7
NSFW_REVIEW = 0.3
NSFW_BLOCK = 0.6
SPAM_BLOCK = 0.75
DANGER_BLOCK = 0.65


@dataclass
class ModerationScores:
    toxicity_score: float = 0.0
    spam_score: float = 0.0
    nsfw_score: float = 0.0
    danger_score: float = 0.0
    decision: str = DECISION_SAFE
    reasons: List[str] = None

    def __post_init__(self):
        if self.reasons is None:
            self.reasons = []

    def to_dict(self) -> Dict[str, Any]:
        return {
            "toxicity_score": round(self.toxicity_score, 3),
            "spam_score": round(self.spam_score, 3),
            "nsfw_score": round(self.nsfw_score, 3),
            "danger_score": round(self.danger_score, 3),
            "ai_decision": self.decision,
            "reasons": self.reasons,
        }


class ModerationPipelineService:
    """Оценка контента перед публикацией / после жалобы."""

    _SPAM_PATTERNS = (
        r"bit\.ly/",
        r"tinyurl\.",
        r"t\.me/",
        r"telegram\.me/",
        r"onlyfans",
        r"казино",
        r"casino",
        r"заработок без вложений",
        r"криптовалют",
        r"viagra",
    )

    def __init__(self):
        self._text = ModerationService()

    def analyze_text(
        self,
        text: str,
        title: Optional[str] = None,
        image_urls: Optional[List[str]] = None,
        trust_score: float = 0.5,
    ) -> ModerationScores:
        full = f"{title or ''}\n{text or ''}".strip()
        scores = ModerationScores()

        if not full and not image_urls:
            return scores

        # OpenAI Moderation API
        if full:
            mod = self._text.check_text(full)
            if mod.get("flagged"):
                raw = float(mod.get("score") or 0.5)
                cat = (mod.get("reason") or "").lower()
                if "sexual" in cat or "nsfw" in cat:
                    scores.nsfw_score = max(scores.nsfw_score, raw)
                elif "violence" in cat or "self-harm" in cat:
                    scores.danger_score = max(scores.danger_score, raw)
                else:
                    scores.toxicity_score = max(scores.toxicity_score, raw)
                scores.reasons.append(mod.get("reason") or "openai_flagged")

        if full:
            scores.spam_score = max(scores.spam_score, self._heuristic_spam(full))
            scores.danger_score = max(scores.danger_score, self._heuristic_danger(full))

        # Изображения: лёгкая проверка URL + опционально OpenAI (V1)
        if image_urls:
            for url in image_urls[:3]:
                img_nsfw = self._text.check_image_url(url) if url else 0.0
                scores.nsfw_score = max(scores.nsfw_score, img_nsfw)

        # Низкий trust → чаще review
        if trust_score < 0.35:
            scores.toxicity_score = min(1.0, scores.toxicity_score + 0.1)
            scores.spam_score = min(1.0, scores.spam_score + 0.1)

        scores.decision = self._decide(scores)
        return scores

    def _heuristic_spam(self, text: str) -> float:
        t = text.lower()
        score = 0.0
        for p in self._SPAM_PATTERNS:
            if re.search(p, t):
                score = max(score, 0.85)
        link_count = len(re.findall(r"https?://", t))
        if link_count >= 3:
            score = max(score, 0.9)
        if len(text) > 20 and len(set(text.split())) < 3:
            score = max(score, 0.7)
        if re.search(r"(.)\1{14,}", text):
            score = max(score, 0.65)
        return score

    def _heuristic_danger(self, text: str) -> float:
        t = text.lower()
        dangerous = (
            "наркотик",
            "оружие",
            "убить",
            "террор",
            "suicide",
            "self-harm",
        )
        for w in dangerous:
            if w in t:
                return 0.8
        return 0.0

    def _decide(self, s: ModerationScores) -> str:
        if (
            s.toxicity_score >= TOXICITY_BLOCK
            or s.nsfw_score >= NSFW_BLOCK
            or s.spam_score >= SPAM_BLOCK
            or s.danger_score >= DANGER_BLOCK
        ):
            return DECISION_BLOCK
        if (
            s.toxicity_score >= TOXICITY_REVIEW
            or s.nsfw_score >= NSFW_REVIEW
            or s.spam_score >= 0.45
            or s.danger_score >= 0.4
        ):
            return DECISION_WARNING
        return DECISION_SAFE
