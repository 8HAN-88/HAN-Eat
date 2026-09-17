"""Реферальные коды, доп. реклама и начисление долей."""
from __future__ import annotations

import re
import secrets
from datetime import datetime, timedelta
from typing import Any, Optional
from urllib.parse import parse_qs, unquote, urlparse

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.revenue_share import (
    APPLY_CODE_MAX_AGE_DAYS,
    CLICK_GROSS_KOPECKS,
    HOLD_DAYS,
    IMPRESSION_GROSS_KOPECKS,
    REFERRAL_DAYS,
    ROLE_REFERRER,
    ROLE_VIEWER,
    SOURCE_ADS,
    SOURCE_SUBSCRIPTION,
    rub_to_kopecks,
    split_kopecks,
)
from app.models.revenue_share import RevenueShareLedger
from app.models.user import User

_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
_WRAP_KEYS = ("u", "url", "q", "to", "link", "text")
_EMBEDDED_INVITE = re.compile(
    r"https?://(?:www\.)?haneat\.app[^\s<>\"']+",
    re.IGNORECASE,
)


def _normalize_referral(raw: Optional[str]) -> Optional[str]:
    value = (raw or "").strip()
    if value.startswith("@"):
        value = value[1:].strip()
    if not value or len(value) > 100:
        return None
    return value


def _query_ci(query: dict[str, list[str]], *names: str) -> str:
    wanted = {name.lower() for name in names}
    for key, items in query.items():
        if (key or "").lower() not in wanted:
            continue
        value = unquote(((items[0] if items else "") or "").strip())
        if value:
            return value
    return ""


def extract_referral(raw: Optional[str], depth: int = 0) -> Optional[str]:
    """Достаёт код из сырого ввода, полной ссылки или обёртки мессенджера."""
    value = (raw or "").strip()
    if not value or depth > 3:
        return None
    parsed = urlparse(value)
    query = parse_qs(parsed.query, keep_blank_values=True)

    def _first(key: str) -> str:
        return _query_ci(query, key)

    ref = _query_ci(query, "ref", "referral")
    if ref:
        if "://" in ref or "ref=" in ref.lower():
            inner = extract_referral(ref, depth + 1)
            if inner:
                return inner
        return _normalize_referral(ref)

    frag = unquote(parsed.fragment or "")
    if "ref=" in frag.lower():
        frag_uri = urlparse(
            f"https://haneat.app{frag}" if frag.startswith("/") else f"https://haneat.app/{frag}"
        )
        href = _query_ci(parse_qs(frag_uri.query, keep_blank_values=True), "ref", "referral")
        if href:
            return extract_referral(href, depth + 1) or _normalize_referral(href)

    for key in _WRAP_KEYS:
        nested = _first(key)
        if not nested:
            continue
        if "haneat.app" in nested or "ref=" in nested:
            inner = extract_referral(nested, depth + 1)
            if inner:
                return inner

    if "://" in value or "haneat.app" in value.lower():
        match = _EMBEDDED_INVITE.search(value)
        if match:
            inner = extract_referral(match.group(0), depth + 1)
            if inner:
                return inner

    return _normalize_referral(value)


class RevenueShareError(Exception):
    def __init__(self, message: str, status_code: int = 400):
        super().__init__(message)
        self.message = message
        self.status_code = status_code


def _now() -> datetime:
    return datetime.utcnow()


def _as_naive_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value
    return value.replace(tzinfo=None)


class RevenueShareService:
    def __init__(self, db: Session):
        self.db = db

    def extra_ads_enabled(self, user_id: int) -> bool:
        user = self.db.query(User).filter(User.id == user_id).first()
        return bool(user and user.extra_ads_enabled)

    def ensure_code(self, user: User) -> str:
        if (user.referral_code or "").strip():
            return user.referral_code.strip()
        for _ in range(12):
            code = "".join(secrets.choice(_CODE_ALPHABET) for _ in range(8))
            taken = (
                self.db.query(User.id)
                .filter(func.upper(User.referral_code) == code)
                .first()
            )
            if taken:
                continue
            user.referral_code = code
            self.db.add(user)
            return code
        raise RevenueShareError("Не удалось выдать реферальный код")

    def _find_referrer(self, raw_code: str) -> Optional[User]:
        code = raw_code.strip()
        if not code:
            return None
        upper = code.upper()
        live = (
            User.deleted_at.is_(None),
            User.banned_at.is_(None),
            User.is_bot.is_(False),
        )
        referrer = (
            self.db.query(User)
            .filter(func.upper(User.referral_code) == upper, *live)
            .first()
        )
        if referrer:
            return referrer
        referrer = (
            self.db.query(User)
            .filter(func.lower(User.username) == code.lower(), *live)
            .first()
        )
        if referrer:
            return referrer
        if upper.startswith("U") and upper[1:].isdigit():
            return (
                self.db.query(User)
                .filter(User.id == int(upper[1:]), *live)
                .first()
            )
        return None

    def attach_after_signup(self, user: User, raw_code: Optional[str]) -> None:
        """Привязка ссылки и выдача своего кода. Ошибки не роняют регистрацию."""
        if raw_code:
            try:
                self.apply_code(user, raw_code)
            except Exception:
                pass
        try:
            self.ensure_code(user)
        except Exception:
            pass

    def apply_code(self, user: User, raw_code: Optional[str]) -> User:
        code = extract_referral(raw_code)
        if not code:
            return user
        if user.referred_by_user_id:
            return user
        created = _as_naive_utc(user.created_at or _now())
        if (_as_naive_utc(_now()) - created) > timedelta(days=APPLY_CODE_MAX_AGE_DAYS):
            raise RevenueShareError(
                "Код можно привязать только в первые 7 дней после регистрации"
            )
        referrer = self._find_referrer(code)
        if not referrer or referrer.id == user.id:
            raise RevenueShareError("Реферальный код не найден")
        user.referred_by_user_id = referrer.id
        user.referred_at = _now()
        self.db.add(user)
        return user

    def set_extra_ads(self, user: User, enabled: bool) -> User:
        user.extra_ads_enabled = bool(enabled)
        user.extra_ads_enabled_at = _now() if enabled else None
        self.db.add(user)
        return user

    def _active_referrer_id(self, user: User) -> Optional[int]:
        if not user.referred_by_user_id or not user.referred_at:
            return None
        if (_as_naive_utc(_now()) - _as_naive_utc(user.referred_at)) > timedelta(
            days=REFERRAL_DAYS
        ):
            return None
        other = (
            self.db.query(User)
            .filter(User.id == user.referred_by_user_id)
            .first()
        )
        if (
            not other
            or other.deleted_at is not None
            or other.banned_at is not None
            or bool(getattr(other, "is_bot", False))
        ):
            return None
        return int(user.referred_by_user_id)

    def _already_booked(
        self,
        *,
        source: str,
        reference_type: str,
        reference_id: int,
        role: str,
    ) -> bool:
        return (
            self.db.query(RevenueShareLedger.id)
            .filter(
                RevenueShareLedger.source == source,
                RevenueShareLedger.reference_type == reference_type,
                RevenueShareLedger.reference_id == reference_id,
                RevenueShareLedger.role == role,
            )
            .first()
            is not None
        )

    def _write_share(
        self,
        *,
        beneficiary_id: int,
        role: str,
        source: str,
        subject_id: int,
        referrer_id: Optional[int],
        extra_ads: bool,
        parts: dict[str, int],
        share: int,
        reference_type: str,
        reference_id: int,
    ) -> None:
        if share <= 0:
            return
        if self._already_booked(
            source=source,
            reference_type=reference_type,
            reference_id=reference_id,
            role=role,
        ):
            return
        available_at = _now() + timedelta(days=HOLD_DAYS)
        self.db.add(
            RevenueShareLedger(
                beneficiary_user_id=beneficiary_id,
                role=role,
                source=source,
                subject_user_id=subject_id,
                referrer_user_id=referrer_id,
                extra_ads=extra_ads,
                gross_kopecks=parts["gross"],
                net_kopecks=parts["net"],
                share_kopecks=share,
                status="pending",
                available_at=available_at,
                reference_type=reference_type,
                reference_id=reference_id,
            )
        )

    def accrue_ad_event(
        self,
        *,
        viewer_id: int,
        kind: str,
        reference_id: int,
    ) -> None:
        viewer = self.db.query(User).filter(User.id == viewer_id).first()
        if (
            not viewer
            or viewer.deleted_at is not None
            or viewer.banned_at is not None
            or bool(getattr(viewer, "is_bot", False))
        ):
            return
        key = (kind or "").strip().lower()
        gross = (
            CLICK_GROSS_KOPECKS if key == "click" else IMPRESSION_GROSS_KOPECKS
        )
        extra = bool(viewer.extra_ads_enabled)
        referrer_id = self._active_referrer_id(viewer)
        parts = split_kopecks(
            gross,
            source=SOURCE_ADS,
            extra_ads=extra,
            has_referrer=referrer_id is not None,
        )
        self._write_share(
            beneficiary_id=viewer.id,
            role=ROLE_VIEWER,
            source=SOURCE_ADS,
            subject_id=viewer.id,
            referrer_id=referrer_id,
            extra_ads=extra,
            parts=parts,
            share=parts["user"],
            reference_type=f"ad_{key}",
            reference_id=reference_id,
        )
        if referrer_id:
            self._write_share(
                beneficiary_id=referrer_id,
                role=ROLE_REFERRER,
                source=SOURCE_ADS,
                subject_id=viewer.id,
                referrer_id=referrer_id,
                extra_ads=extra,
                parts=parts,
                share=parts["referrer"],
                reference_type=f"ad_{key}",
                reference_id=reference_id,
            )

    def accrue_subscription(
        self,
        *,
        payer_id: int,
        amount_rub: float,
        reference_id: int,
    ) -> None:
        payer = self.db.query(User).filter(User.id == payer_id).first()
        if (
            not payer
            or payer.deleted_at is not None
            or payer.banned_at is not None
            or bool(getattr(payer, "is_bot", False))
        ):
            return
        gross = rub_to_kopecks(amount_rub)
        if gross <= 0:
            return
        referrer_id = self._active_referrer_id(payer)
        parts = split_kopecks(
            gross,
            source=SOURCE_SUBSCRIPTION,
            extra_ads=False,
            has_referrer=referrer_id is not None,
        )
        if referrer_id:
            self._write_share(
                beneficiary_id=referrer_id,
                role=ROLE_REFERRER,
                source=SOURCE_SUBSCRIPTION,
                subject_id=payer.id,
                referrer_id=referrer_id,
                extra_ads=False,
                parts=parts,
                share=parts["referrer"],
                reference_type="subscription",
                reference_id=reference_id,
            )

    def void_subscription_share(self, payment_id: str) -> int:
        """Снять долю с возвращённой подписки, пока она в холде или доступна."""
        from app.core.revenue_share import payment_reference_id

        ref = payment_reference_id(payment_id)
        rows = (
            self.db.query(RevenueShareLedger)
            .filter(
                RevenueShareLedger.source == SOURCE_SUBSCRIPTION,
                RevenueShareLedger.reference_type == "subscription",
                RevenueShareLedger.reference_id == ref,
                RevenueShareLedger.status.in_(("pending", "available")),
            )
            .all()
        )
        for row in rows:
            row.status = "void"
        return len(rows)

    def _release_ready(self, user_id: int) -> None:
        now = _now()
        rows = (
            self.db.query(RevenueShareLedger)
            .filter(
                RevenueShareLedger.beneficiary_user_id == user_id,
                RevenueShareLedger.status == "pending",
                RevenueShareLedger.available_at.isnot(None),
            )
            .all()
        )
        for row in rows:
            available = _as_naive_utc(row.available_at)
            if available <= now:
                row.status = "available"

    def snapshot(self, user: User) -> dict[str, Any]:
        self.ensure_code(user)
        self._release_ready(user.id)
        self.db.commit()
        self.db.refresh(user)

        def _sum(role: Optional[str], status: Optional[str]) -> int:
            q = self.db.query(func.coalesce(func.sum(RevenueShareLedger.share_kopecks), 0)).filter(
                RevenueShareLedger.beneficiary_user_id == user.id
            )
            if role:
                q = q.filter(RevenueShareLedger.role == role)
            if status:
                q = q.filter(RevenueShareLedger.status == status)
            return int(q.scalar() or 0)

        referred_count = (
            self.db.query(func.count(User.id))
            .filter(
                User.referred_by_user_id == user.id,
                User.deleted_at.is_(None),
                User.banned_at.is_(None),
            )
            .scalar()
            or 0
        )
        referrer = None
        if user.referred_by_user_id:
            other = (
                self.db.query(User)
                .filter(User.id == user.referred_by_user_id)
                .first()
            )
            if other:
                referrer = {
                    "id": other.id,
                    "name": other.name,
                    "username": other.username,
                    "code": other.referral_code,
                }
        code = (user.referral_code or "").strip()
        return {
            "referral_code": code or None,
            "share_url": f"https://haneat.app/invite?ref={code}" if code else "",
            "extra_ads_enabled": bool(user.extra_ads_enabled),
            "referred_by": referrer,
            "referred_count": int(referred_count),
            "referral_days": REFERRAL_DAYS,
            "hold_days": HOLD_DAYS,
            "pending_kopecks": _sum(None, "pending"),
            "available_kopecks": _sum(None, "available"),
            "as_viewer_kopecks": _sum(ROLE_VIEWER, None),
            "as_referrer_kopecks": _sum(ROLE_REFERRER, None),
            "rules": {
                "net_factor": 0.7,
                "user_ad_share_of_net": 0.5,
                "referrer_share_of_net": 0.25,
                "subscription_user_share": 0,
                "stars_excluded": True,
            },
        }
