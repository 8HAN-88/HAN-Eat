"""
Trust score пользователя (V1): простые правила без ML.
"""
from datetime import datetime, timedelta
from typing import Optional

from sqlalchemy.orm import Session

from app.models.user import User

MIN_TRUST = 0.0
MAX_TRUST = 1.0
DEFAULT_TRUST = 0.5


class TrustScoreService:
    def __init__(self, db: Session):
        self.db = db

    def refresh_baseline(self, user_id: int) -> float:
        """Лёгкое повышение за возраст аккаунта без нарушений."""
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            return DEFAULT_TRUST
        score = float(user.trust_score if user.trust_score is not None else DEFAULT_TRUST)
        if user.created_at:
            ref = user.created_at
            if getattr(ref, "tzinfo", None) is not None:
                ref = ref.replace(tzinfo=None)
            days = (datetime.utcnow() - ref).days
            score = min(MAX_TRUST, score + min(days * 0.002, 0.1))
        user.trust_score = self._clamp(score)
        return user.trust_score

    def on_content_approved(self, user_id: int, delta: float = 0.02) -> None:
        self._adjust(user_id, delta)

    def on_content_rejected(self, user_id: int, delta: float = -0.08) -> None:
        self._adjust(user_id, delta)

    def on_warning(self, user_id: int, delta: float = -0.05) -> None:
        self._adjust(user_id, delta)

    def on_report_upheld(self, user_id: int, delta: float = -0.03) -> None:
        self._adjust(user_id, delta)

    def _adjust(self, user_id: int, delta: float) -> None:
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            return
        base = float(user.trust_score if user.trust_score is not None else DEFAULT_TRUST)
        user.trust_score = self._clamp(base + delta)
        if user.trust_score < 0.25 and not user.shadow_moderation:
            user.shadow_moderation = True
        elif user.trust_score >= 0.4 and user.shadow_moderation:
            user.shadow_moderation = False

    @staticmethod
    def _clamp(v: float) -> float:
        return max(MIN_TRUST, min(MAX_TRUST, round(v, 3)))
