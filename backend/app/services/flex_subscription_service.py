"""Flexible subscription: levels, movable features, placement validator."""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Optional

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.models.flex_subscription import (
    FEATURE_STATUSES,
    FEATURE_TYPES,
    SubscriptionFeature,
    SubscriptionFeatureBlock,
    UserFlexSlot,
    UserFlexSubscription,
)
from app.models.subscription import Subscription

BASE_PRICE_RUB = 39
LEVEL_STEP_RUB = 10
MAX_LEVEL = 10
MIN_LEVEL = 1
PERIOD_DAYS = 30
YEARLY_DAYS = 365
YEARLY_MONTHS = 10
PLANS = ("monthly", "yearly")

AI_FEATURE_SLUGS = frozenset(
    {"ai_recommendations", "ai_priority_speed", "offline_saved_posts"}
)
CREATOR_FEATURE_SLUGS = frozenset(
    {
        "creator_tools",
        "creator_scheduled_posts",
        "creator_analytics",
    }
)
PRO_FEATURE_SLUGS = frozenset({"priority_support"})

# Бывшие тарифы AI / Creator / Pro → уровень гибкой подписки.
LEGACY_TIER_LEVELS = {"ai": 6, "creator": 9, "pro": 10}

DEFAULT_BLOCKS = (
    {"key": "A", "title": "Базовые функции", "min_level": 1, "max_level": 3, "sort_order": 1},
    {"key": "B", "title": "Расширенные функции", "min_level": 4, "max_level": 6, "sort_order": 2},
    {"key": "C", "title": "PRO", "min_level": 7, "max_level": 10, "sort_order": 3},
)

DEFAULT_FEATURES = (
    {
        "slug": "ad_free",
        "title": "Без рекламы",
        "description": "Лента и каналы без промо-вставок.",
        "icon": "block",
        "default_level": 1,
        "min_level": 1,
        "max_level": 1,
        "feature_type": "fixed",
        "movable": False,
        "required": True,
        "block_key": "A",
    },
    {
        "slug": "exclusive_reactions",
        "title": "Эксклюзивные реакции",
        "description": "Дополнительные реакции в чатах и на постах.",
        "icon": "favorite",
        "default_level": 2,
        "min_level": 1,
        "max_level": 3,
        "feature_type": "movable",
        "movable": True,
        "required": False,
        "block_key": "A",
    },
    {
        "slug": "profile_decoration",
        "title": "Оформление профиля",
        "description": "Значок подписчика и оформление карточки профиля.",
        "icon": "palette",
        "default_level": 3,
        "min_level": 1,
        "max_level": 3,
        "feature_type": "movable",
        "movable": True,
        "required": False,
        "block_key": "A",
    },
    {
        "slug": "ai_recommendations",
        "title": "AI-рекомендации",
        "description": "Умная лента и подсказки, что смотреть дальше.",
        "icon": "auto_awesome",
        "default_level": 4,
        "min_level": 4,
        "max_level": 6,
        "feature_type": "blocked",
        "movable": True,
        "required": False,
        "block_key": "B",
    },
    {
        "slug": "ai_priority_speed",
        "title": "Приоритет AI",
        "description": "Быстрее ответы ассистента и переводчика.",
        "icon": "bolt",
        "default_level": 5,
        "min_level": 4,
        "max_level": 6,
        "feature_type": "blocked",
        "movable": True,
        "required": False,
        "block_key": "B",
    },
    {
        "slug": "offline_saved_posts",
        "title": "Офлайн-сохранёнки",
        "description": "Сохранённые посты доступны без сети.",
        "icon": "offline_pin",
        "default_level": 6,
        "min_level": 4,
        "max_level": 6,
        "feature_type": "blocked",
        "movable": True,
        "required": False,
        "block_key": "B",
    },
    {
        "slug": "creator_tools",
        "title": "Инструменты автора",
        "description": "Панель автора, продвижение и закреп постов.",
        "icon": "handyman",
        "default_level": 7,
        "min_level": 7,
        "max_level": 10,
        "feature_type": "premium",
        "movable": True,
        "required": False,
        "block_key": "C",
    },
    {
        "slug": "creator_scheduled_posts",
        "title": "Отложенные посты",
        "description": "Публикация по расписанию в каналах.",
        "icon": "schedule",
        "default_level": 8,
        "min_level": 7,
        "max_level": 10,
        "feature_type": "blocked",
        "movable": True,
        "required": False,
        "block_key": "C",
    },
    {
        "slug": "creator_analytics",
        "title": "Аналитика автора",
        "description": "Расширенная статистика каналов и постов.",
        "icon": "insights",
        "default_level": 9,
        "min_level": 7,
        "max_level": 10,
        "feature_type": "blocked",
        "movable": True,
        "required": False,
        "block_key": "C",
    },
    {
        "slug": "priority_support",
        "title": "Приоритетная поддержка",
        "description": "Обращения обрабатываются вне общей очереди.",
        "icon": "support_agent",
        "default_level": 10,
        "min_level": 10,
        "max_level": 10,
        "feature_type": "fixed",
        "movable": False,
        "required": True,
        "block_key": "C",
    },
)


def price_for_level(level: int) -> int:
    n = max(MIN_LEVEL, min(MAX_LEVEL, int(level)))
    return BASE_PRICE_RUB + (n - 1) * LEVEL_STEP_RUB


def normalize_plan(plan: Optional[str]) -> str:
    return "yearly" if str(plan or "").strip().lower() == "yearly" else "monthly"


def period_days_for(plan: Optional[str]) -> int:
    return YEARLY_DAYS if normalize_plan(plan) == "yearly" else PERIOD_DAYS


def price_for_plan(level: int, plan: Optional[str] = "monthly") -> int:
    monthly = price_for_level(level)
    if normalize_plan(plan) == "yearly":
        return monthly * YEARLY_MONTHS
    return monthly


def _now() -> datetime:
    return datetime.utcnow()


class FlexMoveError(HTTPException):
    def __init__(self, detail: str, *, code: str = "flex_move_forbidden"):
        super().__init__(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"code": code, "message": detail},
        )


class FlexSubscriptionService:
    def __init__(self, db: Session):
        self.db = db

    def ensure_catalog(self) -> None:
        if self.db.query(SubscriptionFeatureBlock).count() == 0:
            for row in DEFAULT_BLOCKS:
                self.db.add(SubscriptionFeatureBlock(**row))
            self.db.flush()
        if self.db.query(SubscriptionFeature).count() == 0:
            for index, row in enumerate(DEFAULT_FEATURES, start=1):
                self.db.add(SubscriptionFeature(sort_order=index, **row))
            self.db.flush()

    def list_blocks(self) -> list[SubscriptionFeatureBlock]:
        self.ensure_catalog()
        return (
            self.db.query(SubscriptionFeatureBlock)
            .order_by(SubscriptionFeatureBlock.sort_order.asc(), SubscriptionFeatureBlock.id.asc())
            .all()
        )

    def list_features(self, *, include_inactive: bool = False) -> list[SubscriptionFeature]:
        self.ensure_catalog()
        q = self.db.query(SubscriptionFeature)
        if not include_inactive:
            q = q.filter(
                SubscriptionFeature.status == "active",
                SubscriptionFeature.available.is_(True),
            )
        return q.order_by(
            SubscriptionFeature.default_level.asc(),
            SubscriptionFeature.sort_order.asc(),
            SubscriptionFeature.id.asc(),
        ).all()

    def get_flex(self, user_id: int) -> Optional[UserFlexSubscription]:
        return (
            self.db.query(UserFlexSubscription)
            .filter(UserFlexSubscription.user_id == user_id)
            .first()
        )

    def is_flex_active(self, user_id: int) -> bool:
        row = self.get_flex(user_id)
        if not row or row.status != "active" or int(row.current_level or 0) < 1:
            return False
        if row.expires_at and row.expires_at <= _now():
            return False
        return True

    def current_level(self, user_id: int) -> int:
        if not self.is_flex_active(user_id):
            return 0
        return int(self.get_flex(user_id).current_level or 0)

    def migrate_legacy_if_needed(self, user_id: int) -> Optional[UserFlexSubscription]:
        """Переносит активный AI/Creator/Pro на эквивалентный уровень flex."""
        if self.is_flex_active(user_id):
            return self.get_flex(user_id)
        from app.models.user import User
        from app.services.subscription_service import SubscriptionService

        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            return None
        svc = SubscriptionService(self.db)
        tier, active = svc.effective_tier(user_id)
        if not active:
            return None
        level = LEGACY_TIER_LEVELS.get(tier)
        if not level:
            return None
        sub = svc.get_user_subscription(user_id)
        expires = sub.expires_at if sub else user.subscription_expires_at
        row = self.activate(user_id, level, months=1, auto_renew=bool(user.subscription_auto_renew))
        if expires:
            row.expires_at = expires
        if sub:
            row.payment_subscription_id = sub.id
        self.db.flush()
        return row

    def _block_map(self) -> dict[str, SubscriptionFeatureBlock]:
        return {b.key: b for b in self.list_blocks()}

    def _user_slots(self, user_id: int) -> dict[int, int]:
        rows = (
            self.db.query(UserFlexSlot)
            .filter(UserFlexSlot.user_id == user_id)
            .all()
        )
        return {r.feature_id: r.assigned_level for r in rows}

    def resolved_layout(self, user_id: Optional[int]) -> list[dict[str, Any]]:
        features = self.list_features()
        overrides = self._user_slots(user_id) if user_id else {}
        used_levels: set[int] = set()
        layout: list[dict[str, Any]] = []
        for feat in features:
            level = int(overrides.get(feat.id) or feat.default_level or 1)
            if level in used_levels:
                level = int(feat.default_level or 1)
            used_levels.add(level)
            layout.append({"feature": feat, "level": level})
        layout.sort(key=lambda item: (item["level"], item["feature"].id))
        return layout

    def feature_level(self, user_id: Optional[int], feature: SubscriptionFeature) -> int:
        if user_id:
            row = (
                self.db.query(UserFlexSlot)
                .filter(
                    UserFlexSlot.user_id == user_id,
                    UserFlexSlot.feature_id == feature.id,
                )
                .first()
            )
            if row:
                return int(row.assigned_level)
        return int(feature.default_level or 1)

    def unlocked_slugs(self, user_id: int) -> set[str]:
        level = self.current_level(user_id)
        if level < 1:
            return set()
        slugs: set[str] = set()
        for item in self.resolved_layout(user_id):
            if int(item["level"]) <= level:
                slugs.add(item["feature"].slug)
        return slugs

    def can_place(
        self,
        feature: SubscriptionFeature,
        target_level: int,
        *,
        moving: bool = True,
    ) -> tuple[bool, str]:
        level = int(target_level)
        if level < MIN_LEVEL or level > MAX_LEVEL:
            return False, "Уровень вне диапазона 1–10"
        if moving and (feature.feature_type == "fixed" or not feature.movable or feature.required and feature.feature_type == "fixed"):
            if feature.feature_type == "fixed" or not bool(feature.movable):
                return False, "Эту функцию нельзя перемещать"
        if level < int(feature.min_level) or level > int(feature.max_level):
            return False, (
                f"Функцию можно поставить только на уровни "
                f"{feature.min_level}–{feature.max_level}"
            )
        if feature.block_key:
            block = self._block_map().get(feature.block_key)
            if block and (level < block.min_level or level > block.max_level):
                return False, (
                    f"Функция из блока «{block.title}» ставится только на "
                    f"{block.min_level}–{block.max_level}"
                )
        if feature.feature_type == "premium" and level < int(feature.min_level):
            return False, f"Premium-функция доступна с уровня {feature.min_level}"
        return True, ""

    def validate_layout(
        self,
        slots: list[dict[str, int]],
        *,
        user_id: Optional[int] = None,
    ) -> list[tuple[SubscriptionFeature, int]]:
        if not slots:
            raise FlexMoveError("Пустая конфигурация", code="flex_empty")
        features = {f.id: f for f in self.list_features()}
        seen_features: set[int] = set()
        seen_levels: set[int] = set()
        resolved: list[tuple[SubscriptionFeature, int]] = []
        for raw in slots:
            fid = int(raw.get("feature_id") or 0)
            level = int(raw.get("level") or 0)
            feat = features.get(fid)
            if not feat:
                raise FlexMoveError("Функция не найдена", code="flex_feature_missing")
            if fid in seen_features:
                raise FlexMoveError("Функция указана дважды", code="flex_duplicate_feature")
            if level in seen_levels:
                raise FlexMoveError("На одном уровне две функции", code="flex_duplicate_level")
            ok, reason = self.can_place(feat, level, moving=True)
            default_level = self.feature_level(user_id, feat) if user_id else int(feat.default_level)
            if level != default_level and not ok:
                raise FlexMoveError(reason)
            if level == int(feat.default_level) or level == default_level:
                ok, reason = self.can_place(feat, level, moving=False)
                if not ok and level != int(feat.default_level):
                    raise FlexMoveError(reason)
            else:
                ok, reason = self.can_place(feat, level, moving=True)
                if not ok:
                    raise FlexMoveError(reason)
            seen_features.add(fid)
            seen_levels.add(level)
            resolved.append((feat, level))

        for feat in features.values():
            if feat.required and feat.id not in seen_features:
                raise FlexMoveError(
                    f"Обязательная функция «{feat.title}» должна остаться в подписке",
                    code="flex_required",
                )
            if feat.required and feat.feature_type == "fixed":
                assigned = next((lvl for f, lvl in resolved if f.id == feat.id), None)
                if assigned is not None and assigned != int(feat.default_level):
                    raise FlexMoveError(
                        f"«{feat.title}» закреплена на уровне {feat.default_level}",
                        code="flex_fixed",
                    )
        return resolved

    def save_layout(self, user_id: int, slots: list[dict[str, int]]) -> list[dict[str, Any]]:
        resolved = self.validate_layout(slots, user_id=user_id)
        (
            self.db.query(UserFlexSlot)
            .filter(UserFlexSlot.user_id == user_id)
            .delete(synchronize_session=False)
        )
        for feat, level in resolved:
            self.db.add(
                UserFlexSlot(user_id=user_id, feature_id=feat.id, assigned_level=level)
            )
        self.db.flush()
        return self.resolved_layout(user_id)

    def move_feature(self, user_id: int, feature_id: int, target_level: int) -> list[dict[str, Any]]:
        layout = self.resolved_layout(user_id)
        moving = next((item for item in layout if item["feature"].id == feature_id), None)
        if not moving:
            raise FlexMoveError("Функция не найдена", code="flex_feature_missing")
        feat: SubscriptionFeature = moving["feature"]
        source = int(moving["level"])
        dest = int(target_level)
        if source == dest:
            return layout
        ok, reason = self.can_place(feat, dest, moving=True)
        if not ok:
            raise FlexMoveError(reason)
        occupant = next((item for item in layout if int(item["level"]) == dest), None)
        if occupant:
            other: SubscriptionFeature = occupant["feature"]
            ok_other, reason_other = self.can_place(other, source, moving=True)
            if not ok_other:
                raise FlexMoveError(reason_other)
            occupant["level"] = source
        moving["level"] = dest
        payload = [
            {"feature_id": item["feature"].id, "level": int(item["level"])}
            for item in layout
        ]
        return self.save_layout(user_id, payload)

    def preview_level_change(self, user_id: int, new_level: int) -> dict[str, Any]:
        dest = max(MIN_LEVEL, min(MAX_LEVEL, int(new_level)))
        current = self.current_level(user_id)
        layout = self.resolved_layout(user_id)
        disabled = [
            item["feature"]
            for item in layout
            if int(item["level"]) > dest
        ]
        added = [
            item["feature"]
            for item in layout
            if current < int(item["level"]) <= dest
        ]
        return {
            "from_level": current,
            "to_level": dest,
            "price_rub": price_for_level(dest),
            "delta_rub": price_for_level(dest) - (price_for_level(current) if current else 0),
            "disabled": disabled,
            "added": added,
            "needs_confirm": dest < current and bool(disabled),
        }

    def remaining_days(self, user_id: int) -> float:
        row = self.get_flex(user_id)
        if not row or not row.expires_at:
            return 0.0
        return max(0.0, (row.expires_at - _now()).total_seconds() / 86400.0)

    def current_plan(self, user_id: int) -> str:
        row = self.get_flex(user_id)
        if row is not None:
            return normalize_plan(getattr(row, "plan", None))
        return "monthly"

    def effective_renewal_level(self, user_id: int) -> int:
        row = self.get_flex(user_id)
        if row and row.pending_level:
            return max(MIN_LEVEL, min(MAX_LEVEL, int(row.pending_level)))
        level = self.current_level(user_id)
        if level >= MIN_LEVEL:
            return level
        if row and int(row.current_level or 0) >= MIN_LEVEL:
            return max(MIN_LEVEL, min(MAX_LEVEL, int(row.current_level)))
        return MIN_LEVEL

    def effective_renewal_plan(self, user_id: int) -> str:
        row = self.get_flex(user_id)
        if row and getattr(row, "pending_plan", None):
            return normalize_plan(row.pending_plan)
        return self.current_plan(user_id)

    def quote_level_change(
        self,
        user_id: int,
        dest_level: int,
        dest_plan: Optional[str] = "monthly",
    ) -> dict[str, Any]:
        dest = max(MIN_LEVEL, min(MAX_LEVEL, int(dest_level)))
        dest_plan = normalize_plan(dest_plan)
        dest_price = price_for_plan(dest, dest_plan)
        current = self.current_level(user_id)
        current_plan = self.current_plan(user_id)
        row = self.get_flex(user_id)
        expires = row.expires_at if row else None
        rem = self.remaining_days(user_id) if self.is_flex_active(user_id) else 0.0
        base = {
            "current_level": current,
            "dest_level": dest,
            "monthly_price": price_for_level(dest),
            "period_price": dest_price,
            "current_monthly_price": price_for_level(current) if current else 0,
            "remaining_days": int(rem),
            "expires_at": expires.isoformat() if expires else None,
            "pending_level": int(row.pending_level) if row and row.pending_level else None,
            "pending_plan": getattr(row, "pending_plan", None) if row else None,
            "keep_expires": False,
            "needs_payment": True,
            "credit_rub": 0.0,
            "amount_due": float(dest_price),
            "kind": "new",
            "plan": dest_plan,
            "current_plan": current_plan,
            "period_days": period_days_for(dest_plan),
        }
        if not self.is_flex_active(user_id) or current < 1:
            return base
        if dest == current and dest_plan == current_plan:
            return {
                **base,
                "kind": "same",
                "amount_due": 0.0,
                "needs_payment": False,
                "keep_expires": True,
            }
        if current_plan == "yearly" and dest_plan == "monthly":
            return {
                **base,
                "kind": "downgrade",
                "amount_due": 0.0,
                "needs_payment": False,
                "keep_expires": True,
                "pending_level": dest,
                "pending_plan": dest_plan,
                "applies_at": expires.isoformat() if expires else None,
            }
        if current_plan == "monthly" and dest_plan == "yearly":
            if rem <= 0.5:
                return {
                    **base,
                    "kind": "upgrade",
                    "amount_due": float(dest_price),
                    "keep_expires": False,
                }
            credit = round(price_for_level(current) * rem / PERIOD_DAYS, 2)
            return {
                **base,
                "kind": "upgrade",
                "amount_due": float(max(round(dest_price - credit, 2), 1.0)),
                "credit_rub": credit,
                "keep_expires": False,
            }
        if dest > current:
            current_price = price_for_plan(current, dest_plan)
            dest_period = period_days_for(dest_plan)
            if rem <= 0.5:
                return {
                    **base,
                    "kind": "upgrade",
                    "amount_due": float(dest_price),
                    "keep_expires": False,
                }
            amount_due = max(round((dest_price - current_price) * rem / dest_period, 2), 1.0)
            return {
                **base,
                "kind": "upgrade",
                "amount_due": float(amount_due),
                "credit_rub": round(current_price * rem / dest_period, 2),
                "keep_expires": True,
            }
        return {
            **base,
            "kind": "downgrade",
            "amount_due": 0.0,
            "needs_payment": False,
            "keep_expires": True,
            "pending_level": dest,
            "pending_plan": dest_plan,
            "applies_at": expires.isoformat() if expires else None,
        }

    def schedule_change(
        self,
        user_id: int,
        dest_level: int,
        dest_plan: Optional[str] = None,
    ) -> UserFlexSubscription:
        dest = max(MIN_LEVEL, min(MAX_LEVEL, int(dest_level)))
        dest_plan = normalize_plan(dest_plan or self.current_plan(user_id))
        row = self.get_flex(user_id)
        if row is None or not self.is_flex_active(user_id):
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                "Нет активной подписки для понижения",
            )
        current = int(row.current_level or 0)
        current_plan = normalize_plan(getattr(row, "plan", None))
        if dest == current and dest_plan == current_plan:
            return self.clear_pending(user_id)
        row.pending_level = dest
        row.pending_plan = dest_plan
        row.pending_level_at = row.expires_at
        self.db.flush()
        return row

    def schedule_downgrade(
        self,
        user_id: int,
        dest_level: int,
        dest_plan: Optional[str] = None,
    ) -> UserFlexSubscription:
        return self.schedule_change(user_id, dest_level, dest_plan)

    def clear_pending(self, user_id: int) -> Optional[UserFlexSubscription]:
        row = self.get_flex(user_id)
        if not row:
            return None
        row.pending_level = None
        row.pending_level_at = None
        row.pending_plan = None
        self.db.flush()
        return row

    def set_auto_renew(self, user_id: int, enabled: bool) -> Optional[UserFlexSubscription]:
        row = self.get_flex(user_id)
        if not row:
            return None
        row.auto_renew = bool(enabled)
        if not enabled:
            row.pending_level = None
            row.pending_level_at = None
            row.pending_plan = None
        self.db.flush()
        return row

    def deactivate(self, user_id: int) -> Optional[UserFlexSubscription]:
        row = self.get_flex(user_id)
        if not row:
            return None
        row.status = "inactive"
        row.auto_renew = False
        row.pending_level = None
        row.pending_level_at = None
        row.pending_plan = None
        self.db.flush()
        return row

    def sync_user(self, user_id: int, *, auto_renew: Optional[bool] = None) -> None:
        from app.models.user import User

        user = self.db.query(User).filter(User.id == user_id).first()
        row = self.get_flex(user_id)
        if not user or not row:
            return
        active = self.is_flex_active(user_id)
        user.subscription_type = "flex" if active else "free"
        user.subscription_status = "active" if active else "expired"
        user.subscription_expires_at = row.expires_at if active else None
        if auto_renew is not None:
            user.subscription_auto_renew = bool(auto_renew)
            row.auto_renew = bool(auto_renew)
        else:
            user.subscription_auto_renew = bool(row.auto_renew)
        self.db.flush()

    def activate(
        self,
        user_id: int,
        level: int,
        *,
        payment_subscription_id: Optional[int] = None,
        months: int = 1,
        auto_renew: bool = False,
        extend_period: bool = True,
        plan: Optional[str] = None,
    ) -> UserFlexSubscription:
        dest = max(MIN_LEVEL, min(MAX_LEVEL, int(level)))
        dest_plan = normalize_plan(plan) if plan is not None else None
        row = self.get_flex(user_id)
        if row is None:
            row = UserFlexSubscription(user_id=user_id, plan=dest_plan or "monthly")
            self.db.add(row)
        add_days = YEARLY_DAYS if dest_plan == "yearly" else PERIOD_DAYS * max(1, months)
        if dest_plan == "yearly":
            add_days = YEARLY_DAYS
        if extend_period or not row.expires_at or row.status != "active":
            expires = _now() + timedelta(days=add_days)
            if (
                extend_period
                and row.expires_at
                and row.expires_at > _now()
                and row.status == "active"
            ):
                expires = row.expires_at + timedelta(days=add_days)
            row.expires_at = expires
        row.current_level = dest
        row.status = "active"
        row.auto_renew = bool(auto_renew)
        row.pending_level = None
        row.pending_level_at = None
        row.pending_plan = None
        if dest_plan is not None:
            row.plan = dest_plan
        if payment_subscription_id:
            row.payment_subscription_id = payment_subscription_id
        self.db.flush()
        return row

    def apply_renewal_period(
        self,
        user_id: int,
        *,
        expires_at: datetime,
        auto_renew: bool,
        payment_subscription_id: Optional[int] = None,
        plan: Optional[str] = None,
    ) -> UserFlexSubscription:
        dest = self.effective_renewal_level(user_id)
        dest_plan = normalize_plan(plan or self.effective_renewal_plan(user_id))
        row = self.get_flex(user_id)
        if row is None:
            row = UserFlexSubscription(user_id=user_id, plan=dest_plan)
            self.db.add(row)
        row.current_level = dest
        row.plan = dest_plan
        row.status = "active"
        row.expires_at = expires_at
        row.auto_renew = bool(auto_renew)
        row.pending_level = None
        row.pending_level_at = None
        row.pending_plan = None
        if payment_subscription_id:
            row.payment_subscription_id = payment_subscription_id
        self.db.flush()
        self.sync_user(user_id, auto_renew=auto_renew)
        return row

    def _cancel_active_subscriptions(self, user_id: int) -> None:
        for sub in self.db.query(Subscription).filter(
            Subscription.user_id == user_id,
            Subscription.status.in_(("active", "trial")),
        ):
            sub.status = "cancelled"
            sub.cancelled_at = _now()

    def record_payment_subscription(
        self,
        user_id: int,
        *,
        level: int,
        amount: float,
        payment_provider: str,
        payment_id: str,
        receipt_url: Optional[str] = None,
        auto_renew: bool = False,
        keep_expires: Optional[bool] = None,
        plan: Optional[str] = "monthly",
    ) -> Subscription:
        dest_plan = normalize_plan(plan)
        quote = self.quote_level_change(user_id, level, dest_plan)
        extend = True
        if keep_expires is not None:
            extend = not bool(keep_expires)
        elif quote["kind"] == "upgrade" and quote.get("keep_expires"):
            extend = False
        self._cancel_active_subscriptions(user_id)
        expires = _now() + timedelta(days=period_days_for(dest_plan))
        row = self.get_flex(user_id)
        if not extend and row and row.expires_at and row.expires_at > _now():
            expires = row.expires_at
        sub = Subscription(
            user_id=user_id,
            plan=dest_plan,
            product="flex",
            status="active",
            payment_provider=payment_provider,
            payment_provider_subscription_id=payment_id,
            amount=amount,
            currency="RUB",
            expires_at=expires,
            auto_renew=bool(auto_renew),
            receipt_url=receipt_url,
            refund_status="none",
        )
        self.db.add(sub)
        self.db.flush()
        self.activate(
            user_id,
            level,
            payment_subscription_id=sub.id,
            months=12 if dest_plan == "yearly" else 1,
            auto_renew=bool(auto_renew),
            extend_period=extend,
            plan=dest_plan,
        )
        row = self.get_flex(user_id)
        if row:
            row.expires_at = expires
            row.plan = dest_plan
        self.sync_user(user_id, auto_renew=auto_renew)
        return sub

    def me_payload(self, user_id: int) -> dict[str, Any]:
        self.ensure_catalog()
        self.migrate_legacy_if_needed(user_id)
        level = self.current_level(user_id)
        layout = self.resolved_layout(user_id)
        next_item = next((item for item in layout if int(item["level"]) == level + 1), None)
        unlocked = {item["feature"].slug for item in layout if int(item["level"]) <= level} if level else set()
        row = self.get_flex(user_id)
        plan = self.current_plan(user_id) if self.is_flex_active(user_id) else "monthly"
        return {
            "current_level": level,
            "price_rub": price_for_level(level) if level else 0,
            "yearly_price_rub": price_for_plan(level, "yearly") if level else 0,
            "next_level": level + 1 if level < MAX_LEVEL else None,
            "next_price_rub": price_for_level(level + 1) if level < MAX_LEVEL else None,
            "max_level": MAX_LEVEL,
            "base_price_rub": BASE_PRICE_RUB,
            "step_price_rub": LEVEL_STEP_RUB,
            "yearly_months": YEARLY_MONTHS,
            "plan": plan,
            "active": self.is_flex_active(user_id),
            "auto_renew": bool(row.auto_renew) if row else False,
            "pending_level": int(row.pending_level) if row and row.pending_level else None,
            "pending_plan": (
                normalize_plan(row.pending_plan)
                if row and getattr(row, "pending_plan", None)
                else None
            ),
            "pending_level_at": (
                row.pending_level_at.isoformat()
                if row and row.pending_level_at
                else None
            ),
            "expires_at": (
                row.expires_at.isoformat()
                if row and row.expires_at
                else None
            ),
            "next_feature": self._feature_item(next_item["feature"], next_item["level"], unlocked)
            if next_item
            else None,
            "levels": [
                self._feature_item(item["feature"], item["level"], unlocked)
                for item in layout
            ],
            "blocks": [self._block_item(b) for b in self.list_blocks()],
        }

    def shop_payload(self, user_id: int) -> dict[str, Any]:
        level = self.current_level(user_id)
        unlocked = self.unlocked_slugs(user_id)
        items = []
        for item in self.resolved_layout(user_id):
            feat = item["feature"]
            assigned = int(item["level"])
            if feat.slug in unlocked:
                state = "available"
            elif assigned == level + 1:
                state = "plus_ten"
            else:
                state = "locked"
            items.append(
                {
                    **self._feature_item(feat, assigned, unlocked),
                    "shop_state": state,
                }
            )
        return {"current_level": level, "features": items}

    def preview_payload(
        self,
        user_id: int,
        level: int,
        plan: Optional[str] = "monthly",
    ) -> dict[str, Any]:
        dest = max(MIN_LEVEL, min(MAX_LEVEL, int(level)))
        dest_plan = normalize_plan(plan)
        change = self.preview_level_change(user_id, dest)
        quote = self.quote_level_change(user_id, dest, dest_plan)
        layout = self.resolved_layout(user_id)
        unlocked_now = {i["feature"].slug for i in layout if int(i["level"]) <= dest}
        return {
            "level": dest,
            "price_rub": change["price_rub"],
            "period_price_rub": quote["period_price"],
            "plan": dest_plan,
            "current_plan": quote["current_plan"],
            "next_level": dest + 1 if dest < MAX_LEVEL else None,
            "next_price_rub": price_for_level(dest + 1) if dest < MAX_LEVEL else None,
            "features": [
                self._feature_item(i["feature"], i["level"], unlocked_now)
                for i in layout
                if int(i["level"]) <= dest
            ],
            "next_feature": self._feature_item(
                next(i["feature"] for i in layout if int(i["level"]) == dest + 1),
                dest + 1,
                unlocked_now,
            )
            if dest < MAX_LEVEL and any(int(i["level"]) == dest + 1 for i in layout)
            else None,
            "disabled": [self._feature_item(f, dest + 1, set()) for f in change["disabled"]],
            "added": [self._feature_item(f, dest, unlocked_now) for f in change["added"]],
            "needs_confirm": change["needs_confirm"] or quote["kind"] == "downgrade",
            "delta_rub": change["delta_rub"],
            "kind": quote["kind"],
            "amount_due": quote["amount_due"],
            "credit_rub": quote["credit_rub"],
            "remaining_days": quote["remaining_days"],
            "keep_expires": quote["keep_expires"],
            "needs_payment": quote["needs_payment"],
            "applies_at": quote.get("applies_at") or quote.get("expires_at"),
            "pending_plan": quote.get("pending_plan"),
        }

    def create_feature(self, data: dict[str, Any]) -> SubscriptionFeature:
        slug = str(data.get("slug") or "").strip().lower()
        if not slug:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "slug required")
        if self.db.query(SubscriptionFeature).filter(SubscriptionFeature.slug == slug).first():
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "slug already exists")
        feat = SubscriptionFeature(**self._feature_fields(data, slug=slug))
        self.db.add(feat)
        self.db.flush()
        return feat

    def update_feature(self, feature_id: int, data: dict[str, Any]) -> SubscriptionFeature:
        feat = self.db.query(SubscriptionFeature).filter(SubscriptionFeature.id == feature_id).first()
        if not feat:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Feature not found")
        fields = self._feature_fields(data, slug=feat.slug, partial=True)
        for key, value in fields.items():
            setattr(feat, key, value)
        self.db.flush()
        return feat

    def upsert_block(self, data: dict[str, Any], block_id: Optional[int] = None) -> SubscriptionFeatureBlock:
        if block_id:
            block = (
                self.db.query(SubscriptionFeatureBlock)
                .filter(SubscriptionFeatureBlock.id == block_id)
                .first()
            )
            if not block:
                raise HTTPException(status.HTTP_404_NOT_FOUND, "Block not found")
        else:
            key = str(data.get("key") or "").strip()
            if not key:
                raise HTTPException(status.HTTP_400_BAD_REQUEST, "key required")
            block = (
                self.db.query(SubscriptionFeatureBlock)
                .filter(SubscriptionFeatureBlock.key == key)
                .first()
            )
            if block is None:
                block = SubscriptionFeatureBlock(key=key)
                self.db.add(block)
        if "title" in data and data["title"] is not None:
            block.title = str(data["title"]).strip() or block.title
        if "min_level" in data and data["min_level"] is not None:
            block.min_level = int(data["min_level"])
        if "max_level" in data and data["max_level"] is not None:
            block.max_level = int(data["max_level"])
        if "sort_order" in data and data["sort_order"] is not None:
            block.sort_order = int(data["sort_order"])
        self.db.flush()
        return block

    def _feature_fields(
        self, data: dict[str, Any], *, slug: str, partial: bool = False
    ) -> dict[str, Any]:
        out: dict[str, Any] = {}
        if not partial:
            out["slug"] = slug
            out["title"] = str(data.get("title") or slug).strip()
        elif "title" in data and data["title"] is not None:
            out["title"] = str(data["title"]).strip()
        mapping = {
            "description": lambda v: (str(v).strip() if v is not None else None),
            "icon": lambda v: (str(v).strip() if v else None),
            "price_rub": lambda v: v,
            "min_level": lambda v: max(MIN_LEVEL, min(MAX_LEVEL, int(v))),
            "max_level": lambda v: max(MIN_LEVEL, min(MAX_LEVEL, int(v))),
            "default_level": lambda v: max(MIN_LEVEL, min(MAX_LEVEL, int(v))),
            "feature_type": lambda v: (
                str(v).strip().lower()
                if str(v).strip().lower() in FEATURE_TYPES
                else "movable"
            ),
            "movable": lambda v: bool(v),
            "required": lambda v: bool(v),
            "block_key": lambda v: (str(v).strip() if v else None),
            "launch_at": lambda v: v,
            "status": lambda v: (
                str(v).strip().lower()
                if str(v).strip().lower() in FEATURE_STATUSES
                else "active"
            ),
            "available": lambda v: bool(v),
            "sort_order": lambda v: int(v or 0),
        }
        for key, caster in mapping.items():
            if key in data or not partial:
                if key in data:
                    out[key] = caster(data.get(key))
                elif not partial and key not in out:
                    continue
        if out.get("feature_type") == "fixed":
            out["movable"] = False
        return out

    @staticmethod
    def _block_item(block: SubscriptionFeatureBlock) -> dict[str, Any]:
        return {
            "id": block.id,
            "key": block.key,
            "title": block.title,
            "min_level": block.min_level,
            "max_level": block.max_level,
            "sort_order": block.sort_order,
        }

    @staticmethod
    def _feature_item(
        feat: SubscriptionFeature,
        level: int,
        unlocked: set[str],
    ) -> dict[str, Any]:
        return {
            "id": feat.id,
            "slug": feat.slug,
            "title": feat.title,
            "description": feat.description,
            "icon": feat.icon,
            "price_rub": float(feat.price_rub) if feat.price_rub is not None else None,
            "min_level": feat.min_level,
            "max_level": feat.max_level,
            "default_level": feat.default_level,
            "assigned_level": level,
            "feature_type": feat.feature_type,
            "movable": bool(feat.movable) and feat.feature_type != "fixed",
            "required": bool(feat.required),
            "block_key": feat.block_key,
            "status": feat.status,
            "available": bool(feat.available),
            "unlocked": feat.slug in unlocked,
            "launch_at": feat.launch_at.isoformat() if feat.launch_at else None,
        }
