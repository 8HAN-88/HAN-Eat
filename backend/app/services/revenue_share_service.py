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
    KIND_CARD,
    KIND_STARS,
    KOPECKS_PER_STAR,
    MIN_CARD_PAYOUT_KOPECKS,
    REFERRAL_DAYS,
    ROLE_REFERRER,
    ROLE_VIEWER,
    SOURCE_ADS,
    SOURCE_SUBSCRIPTION,
    STATUS_AVAILABLE,
    STATUS_PAID,
    STATUS_PAYOUT_HOLD,
    STATUS_PENDING,
    STATUS_REJECTED,
    STATUS_VOID,
    rub_to_kopecks,
    split_kopecks,
)
from app.models.revenue_share import PartnerPayoutRequest, RevenueShareLedger
from app.models.user import User

_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
_WRAP_KEYS = ("u", "url", "q", "to", "link", "text")
_EMBEDDED_INVITE = re.compile(
    r"https?://(?:www\.)?haneat\.app[^\s<>\"']+",
    re.IGNORECASE,
)


_ZW = re.compile(r"[\u200b\u200c\u200d\ufeff\u00ad]")
_TRAIL_PUNCT = re.compile(r"""[.,;:!?\)\]\}'"…/]+$""")


def _sanitize_referral_input(raw: str) -> str:
    value = _ZW.sub("", raw or "")
    value = value.replace("\u00a0", " ")
    value = (
        value.replace("&amp;", "&").replace("&AMP;", "&").replace("&#38;", "&")
    )
    return value.strip()


def _normalize_referral(raw: Optional[str]) -> Optional[str]:
    value = _sanitize_referral_input(raw or "")
    if value.startswith("@"):
        value = value[1:].strip()
    value = _TRAIL_PUNCT.sub("", value)
    if not value or len(value) > 100:
        return None
    return value


def _query_ci(query: dict[str, list[str]], *names: str) -> str:
    wanted = {name.lower() for name in names}
    for key, items in query.items():
        lowered = (key or "").lower()
        if lowered.startswith("amp;"):
            lowered = lowered[4:]
        if lowered not in wanted:
            continue
        value = unquote(((items[0] if items else "") or "").strip())
        if value:
            return value
    return ""


def extract_referral(raw: Optional[str], depth: int = 0) -> Optional[str]:
    """Достаёт код из сырого ввода, полной ссылки или обёртки мессенджера."""
    value = _sanitize_referral_input(raw or "")
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
        if "haneat.app" in nested.lower() or "ref=" in nested.lower():
            inner = extract_referral(nested, depth + 1)
            if inner:
                return inner

    parts = [item for item in (parsed.path or "").split("/") if item]
    invite_at = next(
        (i for i, item in enumerate(parts) if item.lower() == "invite"),
        -1,
    )
    if invite_at >= 0 and invite_at + 1 < len(parts):
        token = parts[invite_at + 1]
        if token.lower() not in {"index.html", "app"}:
            inner = extract_referral(token, depth + 1) or _normalize_referral(token)
            if inner:
                return inner

    if "://" in value or "haneat.app" in value.lower():
        match = _EMBEDDED_INVITE.search(value)
        if match and match.group(0) != value:
            inner = extract_referral(match.group(0), depth + 1)
            if inner:
                return inner
        return None

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
            if code.startswith("U") and code[1:].isdigit():
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
        if bool(getattr(user, "is_bot", False)):
            raise RevenueShareError("Реферальный код не найден")
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
                status=STATUS_PENDING,
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
                RevenueShareLedger.status.in_((STATUS_PENDING, STATUS_AVAILABLE)),
            )
            .all()
        )
        for row in rows:
            row.status = STATUS_VOID
        return len(rows)

    def _release_ready(self, user_id: int) -> None:
        now = _now()
        rows = (
            self.db.query(RevenueShareLedger)
            .filter(
                RevenueShareLedger.beneficiary_user_id == user_id,
                RevenueShareLedger.status == STATUS_PENDING,
                RevenueShareLedger.available_at.isnot(None),
            )
            .all()
        )
        for row in rows:
            available = _as_naive_utc(row.available_at)
            if available <= now:
                row.status = STATUS_AVAILABLE

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
                User.is_bot.is_(False),
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
        available = _sum(None, STATUS_AVAILABLE)
        return {
            "referral_code": code or None,
            "share_url": f"https://haneat.app/invite?ref={code}" if code else "",
            "extra_ads_enabled": bool(user.extra_ads_enabled),
            "referred_by": referrer,
            "referred_count": int(referred_count),
            "referral_days": REFERRAL_DAYS,
            "hold_days": HOLD_DAYS,
            "pending_kopecks": _sum(None, STATUS_PENDING),
            "available_kopecks": available,
            "payout_hold_kopecks": _sum(None, STATUS_PAYOUT_HOLD),
            "paid_kopecks": _sum(None, STATUS_PAID),
            "as_viewer_kopecks": _sum(ROLE_VIEWER, None),
            "as_referrer_kopecks": _sum(ROLE_REFERRER, None),
            "kopecks_per_star": KOPECKS_PER_STAR,
            "min_card_kopecks": MIN_CARD_PAYOUT_KOPECKS,
            "convertible_stars": available // KOPECKS_PER_STAR,
            "payouts": [self._payout_dict(row) for row in self.list_my_payouts(user.id)],
            "rules": {
                "net_factor": 0.7,
                "user_ad_share_of_net": 0.5,
                "referrer_share_of_net": 0.25,
                "subscription_user_share": 0,
                "stars_excluded": True,
                "kopecks_per_star": KOPECKS_PER_STAR,
                "min_card_kopecks": MIN_CARD_PAYOUT_KOPECKS,
            },
        }

    def _iso(self, value: Optional[datetime]) -> Optional[str]:
        if value is None:
            return None
        naive = _as_naive_utc(value)
        return naive.isoformat() + "Z"

    def _payout_dict(
        self,
        payout: PartnerPayoutRequest,
        *,
        with_user: bool = False,
    ) -> dict[str, Any]:
        data: dict[str, Any] = {
            "id": payout.id,
            "user_id": payout.user_id,
            "kind": payout.kind,
            "amount_kopecks": int(payout.amount_kopecks or 0),
            "amount_stars": int(payout.amount_stars or 0),
            "status": payout.status,
            "phone": payout.phone,
            "recipient_name": payout.recipient_name,
            "note": payout.note,
            "created_at": self._iso(payout.created_at),
            "reviewed_at": self._iso(payout.reviewed_at),
            "paid_at": self._iso(payout.paid_at),
        }
        if with_user:
            other = self.db.query(User).filter(User.id == payout.user_id).first()
            if other:
                data["user_name"] = other.name
                data["user_email"] = other.email
                data["user_username"] = other.username
        return data

    def _live_user(self, user: User) -> User:
        if user.deleted_at is not None or user.banned_at is not None:
            raise RevenueShareError("Аккаунт недоступен", status_code=403)
        if bool(getattr(user, "is_bot", False)):
            raise RevenueShareError("Выплаты ботам недоступны")
        return user

    def _available_rows(self, user_id: int) -> list[RevenueShareLedger]:
        self._release_ready(user_id)
        return (
            self.db.query(RevenueShareLedger)
            .filter(
                RevenueShareLedger.beneficiary_user_id == user_id,
                RevenueShareLedger.status == STATUS_AVAILABLE,
            )
            .order_by(
                RevenueShareLedger.available_at.asc(),
                RevenueShareLedger.id.asc(),
            )
            .with_for_update()
            .all()
        )

    def _allocate_available(
        self,
        *,
        user_id: int,
        amount_kopecks: int,
        payout: PartnerPayoutRequest,
        status: str,
    ) -> None:
        if amount_kopecks <= 0:
            raise RevenueShareError("Сумма должна быть больше нуля")
        rows = self._available_rows(user_id)
        total = sum(int(row.share_kopecks or 0) for row in rows)
        if total < amount_kopecks:
            raise RevenueShareError("Недостаточно доступного баланса")
        taken: list[RevenueShareLedger] = []
        acc = 0
        for row in rows:
            taken.append(row)
            acc += int(row.share_kopecks or 0)
            if acc >= amount_kopecks:
                break
        overshoot = acc - amount_kopecks
        last = taken[-1]
        if overshoot > 0:
            last_share = int(last.share_kopecks or 0)
            keep = last_share - overshoot
            if keep <= 0:
                raise RevenueShareError("Не удалось разделить строку баланса")
            last.share_kopecks = keep
            self.db.add(
                RevenueShareLedger(
                    beneficiary_user_id=last.beneficiary_user_id,
                    role=last.role,
                    source="payout",
                    subject_user_id=last.subject_user_id,
                    referrer_user_id=last.referrer_user_id,
                    extra_ads=bool(last.extra_ads),
                    gross_kopecks=0,
                    net_kopecks=0,
                    share_kopecks=overshoot,
                    status=STATUS_AVAILABLE,
                    available_at=_now(),
                    reference_type="payout_change",
                    reference_id=payout.id,
                )
            )
        for row in taken:
            row.status = status
            row.payout_request_id = payout.id

    def _normalize_phone(self, raw: Optional[str]) -> str:
        digits = re.sub(r"\D", "", raw or "")
        if digits.startswith("8") and len(digits) == 11:
            digits = "7" + digits[1:]
        if digits.startswith("9") and len(digits) == 10:
            digits = "7" + digits
        if len(digits) != 11 or not digits.startswith("7"):
            raise RevenueShareError("Укажите телефон СБП в формате +7…")
        return "+" + digits

    def _normalize_name(self, raw: Optional[str]) -> str:
        name = re.sub(r"\s+", " ", (raw or "").strip())
        if len(name) < 2 or len(name) > 80:
            raise RevenueShareError("Укажите имя получателя")
        return name

    def list_my_payouts(self, user_id: int, *, limit: int = 40) -> list[PartnerPayoutRequest]:
        return (
            self.db.query(PartnerPayoutRequest)
            .filter(PartnerPayoutRequest.user_id == user_id)
            .order_by(
                PartnerPayoutRequest.created_at.desc(),
                PartnerPayoutRequest.id.desc(),
            )
            .limit(max(1, min(limit, 200)))
            .all()
        )

    def list_payout_queue(
        self,
        *,
        status: Optional[str] = STATUS_PENDING,
        limit: int = 100,
    ) -> list[dict[str, Any]]:
        q = self.db.query(PartnerPayoutRequest).filter(
            PartnerPayoutRequest.kind == KIND_CARD
        )
        if status:
            q = q.filter(PartnerPayoutRequest.status == status)
        rows = (
            q.order_by(
                PartnerPayoutRequest.created_at.asc(),
                PartnerPayoutRequest.id.asc(),
            )
            .limit(max(1, min(limit, 200)))
            .all()
        )
        return [self._payout_dict(row, with_user=True) for row in rows]

    def convert_to_stars(
        self,
        user: User,
        amount_kopecks: Optional[int] = None,
    ) -> PartnerPayoutRequest:
        self._live_user(user)
        self._release_ready(user.id)
        available = int(
            self.db.query(func.coalesce(func.sum(RevenueShareLedger.share_kopecks), 0))
            .filter(
                RevenueShareLedger.beneficiary_user_id == user.id,
                RevenueShareLedger.status == STATUS_AVAILABLE,
            )
            .scalar()
            or 0
        )
        spendable = available if amount_kopecks is None else min(available, int(amount_kopecks))
        stars = spendable // KOPECKS_PER_STAR
        if stars < 1:
            raise RevenueShareError("Нужна хотя бы 1 звезда (от 0,80 ₽)")
        need = stars * KOPECKS_PER_STAR
        payout = PartnerPayoutRequest(
            user_id=user.id,
            kind=KIND_STARS,
            amount_kopecks=need,
            amount_stars=stars,
            status=STATUS_PAID,
            paid_at=_now(),
            created_at=_now(),
        )
        self.db.add(payout)
        self.db.flush()
        self._allocate_available(
            user_id=user.id,
            amount_kopecks=need,
            payout=payout,
            status=STATUS_PAID,
        )
        from app.services.paid_features_service import PaidFeaturesService

        PaidFeaturesService(self.db).add_stars(
            user.id,
            stars,
            tx_type="partner_payout",
            idempotency_key=f"partner_payout:{payout.id}",
            meta={"payout_id": payout.id, "kopecks": need},
        )
        self.db.flush()
        return payout

    def request_card_payout(
        self,
        user: User,
        *,
        amount_kopecks: Optional[int],
        phone: str,
        recipient_name: str,
        note: Optional[str] = None,
    ) -> PartnerPayoutRequest:
        self._live_user(user)
        self._release_ready(user.id)
        available = int(
            self.db.query(func.coalesce(func.sum(RevenueShareLedger.share_kopecks), 0))
            .filter(
                RevenueShareLedger.beneficiary_user_id == user.id,
                RevenueShareLedger.status == STATUS_AVAILABLE,
            )
            .scalar()
            or 0
        )
        requested = available if amount_kopecks is None else int(amount_kopecks)
        if requested < MIN_CARD_PAYOUT_KOPECKS:
            raise RevenueShareError("На карту — от 500 ₽")
        if requested > available:
            raise RevenueShareError("Недостаточно доступного баланса")
        payout = PartnerPayoutRequest(
            user_id=user.id,
            kind=KIND_CARD,
            amount_kopecks=requested,
            amount_stars=0,
            status=STATUS_PENDING,
            phone=self._normalize_phone(phone),
            recipient_name=self._normalize_name(recipient_name),
            note=(note or "").strip() or None,
            created_at=_now(),
        )
        self.db.add(payout)
        self.db.flush()
        self._allocate_available(
            user_id=user.id,
            amount_kopecks=requested,
            payout=payout,
            status=STATUS_PAYOUT_HOLD,
        )
        self.db.flush()
        return payout

    def review_payout(
        self,
        payout_id: int,
        *,
        reviewer_user_id: int,
        approve: bool,
        note: Optional[str] = None,
    ) -> PartnerPayoutRequest:
        payout = (
            self.db.query(PartnerPayoutRequest)
            .filter(PartnerPayoutRequest.id == payout_id)
            .first()
        )
        if not payout:
            raise RevenueShareError("Заявка не найдена", status_code=404)
        if payout.kind != KIND_CARD:
            raise RevenueShareError("Эту заявку нельзя разобрать вручную")
        if payout.status != STATUS_PENDING:
            raise RevenueShareError("Заявка уже разобрана")
        payout.reviewed_by_user_id = reviewer_user_id
        payout.reviewed_at = _now()
        if note is not None:
            payout.note = note.strip() or payout.note
        rows = (
            self.db.query(RevenueShareLedger)
            .filter(RevenueShareLedger.payout_request_id == payout.id)
            .all()
        )
        if approve:
            payout.status = STATUS_PAID
            payout.paid_at = _now()
            for row in rows:
                if row.status == STATUS_PAYOUT_HOLD:
                    row.status = STATUS_PAID
        else:
            payout.status = STATUS_REJECTED
            for row in rows:
                if row.status == STATUS_PAYOUT_HOLD:
                    row.status = STATUS_AVAILABLE
                    row.payout_request_id = None
        self.db.flush()
        return payout
