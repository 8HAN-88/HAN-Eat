"""Сохранение и загрузка AI-планов в Postgres."""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from app.models.ai_meal_plan_record import AiMealPlanRecord


class MealPlanStorageService:
    def __init__(self, db: Session):
        self.db = db

    def save_plan(
        self,
        user_id: int,
        plan: Dict[str, Any],
        *,
        family_size: int = 1,
    ) -> AiMealPlanRecord:
        plan_id = str(plan.get("plan_id") or "")
        duration = int(plan.get("duration_days") or 3)
        existing = (
            self.db.query(AiMealPlanRecord)
            .filter(
                AiMealPlanRecord.user_id == user_id,
                AiMealPlanRecord.plan_id == plan_id,
            )
            .first()
        )
        if existing:
            existing.plan_data = plan
            existing.duration_days = duration
            existing.family_size = family_size
            self.db.flush()
            return existing

        row = AiMealPlanRecord(
            user_id=user_id,
            plan_id=plan_id,
            duration_days=duration,
            family_size=family_size,
            plan_data=plan,
        )
        self.db.add(row)
        self.db.flush()
        return row

    def get_latest(self, user_id: int) -> Optional[Dict[str, Any]]:
        row = (
            self.db.query(AiMealPlanRecord)
            .filter(AiMealPlanRecord.user_id == user_id)
            .order_by(AiMealPlanRecord.updated_at.desc())
            .first()
        )
        return row.plan_data if row else None

    def list_plans(self, user_id: int, limit: int = 10) -> List[Dict[str, Any]]:
        rows = (
            self.db.query(AiMealPlanRecord)
            .filter(AiMealPlanRecord.user_id == user_id)
            .order_by(AiMealPlanRecord.updated_at.desc())
            .limit(limit)
            .all()
        )
        return [
            {
                "id": r.id,
                "plan_id": r.plan_id,
                "duration_days": r.duration_days,
                "family_size": r.family_size,
                "created_at": r.created_at.isoformat() if r.created_at else None,
                "ai_recommendation": (r.plan_data or {}).get("ai_recommendation"),
                "plan": r.plan_data,
            }
            for r in rows
        ]

    def get_by_plan_id(self, user_id: int, plan_id: str) -> Optional[Dict[str, Any]]:
        row = (
            self.db.query(AiMealPlanRecord)
            .filter(
                AiMealPlanRecord.user_id == user_id,
                AiMealPlanRecord.plan_id == plan_id,
            )
            .first()
        )
        return row.plan_data if row else None
