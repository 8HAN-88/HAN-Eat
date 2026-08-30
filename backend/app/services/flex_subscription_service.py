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
from app.core.flex_catalog import (
    BASE_PRICE_RUB,
    DEFAULT_BLOCKS,
    DEFAULT_FEATURES,
    LEVEL_STEP_RUB,
    MAX_LEVEL,
    MIN_LEVEL,
)
from app.models.subscription import Subscription

# Compact 10-level catalog → one feature per step. Apply once, highest first.
COMPACT_LEVEL_TO_LONG = {
    1: 1,
    2: 4,
    3: 6,
    4: 7,
    5: 8,
    6: 9,
    7: 11,
    8: 14,
    9: 16,
    10: 18,
}

AI_FEATURE_SLUGS = frozenset(
    {"ai_recommendations", "ai_priority_speed", "offline_saved_posts"}
)
CREATOR_FEATURE_SLUGS = frozenset(
    {
        "creator_tools",
        "creator_scheduled_posts",
        "creator_analytics",
        "creator_promotion",
        "creator_badge",
        "creator_pinned",
        "advanced_stats",
    }
)
PRO_FEATURE_SLUGS = frozenset({"priority_support", "pro"})


def remap_compact_level(level: int) -> int:
    n = int(level or 0)
    return COMPACT_LEVEL_TO_LONG.get(n, n)


def price_for_level(level: int) -> int:
    n = max(MIN_LEVEL, min(MAX_LEVEL, int(level)))
    return BASE_PRICE_RUB + (n - 1) * LEVEL_STEP_RUB


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
        existing_features = {
            row.slug: row for row in self.db.query(SubscriptionFeature).all()
        }
        pro = existing_features.get("pro")
        compact_catalog = pro is not None and int(pro.default_level or 0) <= 10
        existing_blocks = {
            row.key: row for row in self.db.query(SubscriptionFeatureBlock).all()
        }
        for row in DEFAULT_BLOCKS:
            current = existing_blocks.get(row["key"])
            if current is None:
                self.db.add(SubscriptionFeatureBlock(**row))
                continue
            current.title = row["title"]
            current.min_level = row["min_level"]
            current.max_level = row["max_level"]
            current.sort_order = row["sort_order"]
        existing = existing_features
        next_order = len(existing)
        for index, row in enumerate(DEFAULT_FEATURES, start=1):
            current = existing.get(row["slug"])
            if current is not None:
                current.title = row["title"]
                current.description = row["description"]
                current.icon = row["icon"]
                current.block_key = row["block_key"]
                current.default_level = row["default_level"]
                current.min_level = row["min_level"]
                current.max_level = row["max_level"]
                current.feature_type = row["feature_type"]
                current.movable = row["movable"]
                current.required = row["required"]
                current.sort_order = index
                continue
            next_order += 1
            self.db.add(SubscriptionFeature(sort_order=next_order or index, **row))
        self.db.flush()
        if compact_catalog:
            self.remap_compact_subscribers()

    def remap_compact_subscribers(self) -> int:
        """Map paid 1–10 compact levels onto the long staircase. Idempotent if anyone is already above 10."""
        rows = self.db.query(UserFlexSubscription).all()
        if not rows:
            return 0
        if any(int(row.current_level or 0) > 10 for row in rows):
            return 0
        changed = 0
        for row in rows:
            mapped = remap_compact_level(int(row.current_level or 0))
            if mapped != int(row.current_level or 0):
                row.current_level = mapped
                changed += 1
        features = {feat.id: feat for feat in self.db.query(SubscriptionFeature).all()}
        for slot in self.db.query(UserFlexSlot).all():
            mapped = remap_compact_level(int(slot.assigned_level or 0))
            feat = features.get(slot.feature_id)
            if feat is not None:
                mapped = max(int(feat.min_level), min(int(feat.max_level), mapped))
            slot.assigned_level = mapped
        self.db.flush()
        return changed

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
        layout: list[dict[str, Any]] = []
        for feat in features:
            level = int(overrides.get(feat.id) or feat.default_level or 1)
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
        resolved: list[tuple[SubscriptionFeature, int]] = []
        for raw in slots:
            fid = int(raw.get("feature_id") or 0)
            level = int(raw.get("level") or 0)
            feat = features.get(fid)
            if not feat:
                raise FlexMoveError("Функция не найдена", code="flex_feature_missing")
            if fid in seen_features:
                raise FlexMoveError("Функция указана дважды", code="flex_duplicate_feature")
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
        dest = int(target_level)
        if int(moving["level"]) == dest:
            return layout
        ok, reason = self.can_place(feat, dest, moving=True)
        if not ok:
            raise FlexMoveError(reason)
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

    def activate(
        self,
        user_id: int,
        level: int,
        *,
        payment_subscription_id: Optional[int] = None,
        months: int = 1,
        auto_renew: bool = False,
    ) -> UserFlexSubscription:
        dest = max(MIN_LEVEL, min(MAX_LEVEL, int(level)))
        row = self.get_flex(user_id)
        expires = _now() + timedelta(days=30 * max(1, months))
        if row and row.expires_at and row.expires_at > _now() and row.status == "active":
            expires = row.expires_at + timedelta(days=30 * max(1, months))
        if row is None:
            row = UserFlexSubscription(user_id=user_id)
            self.db.add(row)
        row.current_level = dest
        row.status = "active"
        row.expires_at = expires
        row.auto_renew = bool(auto_renew)
        if payment_subscription_id:
            row.payment_subscription_id = payment_subscription_id
        self.db.flush()
        return row

    def record_payment_subscription(
        self,
        user_id: int,
        *,
        level: int,
        amount: float,
        payment_provider: str,
        payment_id: str,
        receipt_url: Optional[str] = None,
    ) -> Subscription:
        sub = Subscription(
            user_id=user_id,
            plan="monthly",
            product="flex",
            status="active",
            payment_provider=payment_provider,
            payment_provider_subscription_id=payment_id,
            amount=amount,
            currency="RUB",
            expires_at=_now() + timedelta(days=30),
            auto_renew=False,
            receipt_url=receipt_url,
            refund_status="none",
        )
        self.db.add(sub)
        self.db.flush()
        self.activate(
            user_id,
            level,
            payment_subscription_id=sub.id,
            months=1,
            auto_renew=False,
        )
        return sub

    def me_payload(self, user_id: int) -> dict[str, Any]:
        self.ensure_catalog()
        level = self.current_level(user_id)
        layout = self.resolved_layout(user_id)
        next_item = next((item for item in layout if int(item["level"]) == level + 1), None)
        unlocked = {item["feature"].slug for item in layout if int(item["level"]) <= level} if level else set()
        return {
            "current_level": level,
            "price_rub": price_for_level(level) if level else 0,
            "next_level": level + 1 if level < MAX_LEVEL else None,
            "next_price_rub": price_for_level(level + 1) if level < MAX_LEVEL else None,
            "max_level": MAX_LEVEL,
            "base_price_rub": BASE_PRICE_RUB,
            "step_price_rub": LEVEL_STEP_RUB,
            "active": self.is_flex_active(user_id),
            "expires_at": (
                self.get_flex(user_id).expires_at.isoformat()
                if self.get_flex(user_id) and self.get_flex(user_id).expires_at
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

    def preview_payload(self, user_id: int, level: int) -> dict[str, Any]:
        dest = max(MIN_LEVEL, min(MAX_LEVEL, int(level)))
        change = self.preview_level_change(user_id, dest)
        layout = self.resolved_layout(user_id)
        unlocked_now = {i["feature"].slug for i in layout if int(i["level"]) <= dest}
        return {
            "level": dest,
            "price_rub": change["price_rub"],
            "next_level": dest + 1 if dest < MAX_LEVEL else None,
            "next_price_rub": price_for_level(dest + 1) if dest < MAX_LEVEL else None,
            "features": [
                self._feature_item(i["feature"], i["level"], unlocked_now)
                for i in layout
                if int(i["level"]) <= dest
            ],
            "next_features": [
                self._feature_item(i["feature"], dest + 1, unlocked_now)
                for i in layout
                if dest < MAX_LEVEL and int(i["level"]) == dest + 1
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
            "needs_confirm": change["needs_confirm"],
            "delta_rub": change["delta_rub"],
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
