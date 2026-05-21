"""Планировщик разнообразия блюд с настройками повторов от пользователя."""
from __future__ import annotations

import random
from typing import Any, Dict, List, Optional, Set


class MealVarietyPlanner:
    """
    Подбирает шаблоны с учётом:
    - allow_meal_repeats=False — не повторять блюдо в рамках плана (насколько хватает пула);
    - allow_meal_repeats=True — повтор не раньше meal_repeat_interval_days;
    - не ставить то же блюдо на соседние дни в одном слоте, если есть альтернатива.
    """

    def __init__(
        self,
        duration_days: int,
        *,
        allow_repeats: bool = True,
        repeat_interval_days: int = 4,
        existing_usage: Optional[Dict[str, List[int]]] = None,
        variation_seed: Optional[int] = None,
    ):
        self.duration_days = max(1, duration_days)
        self.allow_repeats = allow_repeats
        interval = max(1, min(21, int(repeat_interval_days)))
        if allow_repeats:
            self.repeat_gap = interval
        else:
            # В пределах плана — без повторов (при нехватке шаблонов — fallback)
            self.repeat_gap = self.duration_days
        self._usage: Dict[str, List[int]] = dict(existing_usage or {})
        self._slot_last: Dict[str, str] = {}
        self._rng = random.Random(variation_seed)

    @classmethod
    def from_preferences(
        cls,
        duration_days: int,
        *,
        allow_meal_repeats: bool = True,
        meal_repeat_interval_days: int = 4,
        existing_usage: Optional[Dict[str, List[int]]] = None,
        variation_seed: Optional[int] = None,
    ) -> "MealVarietyPlanner":
        return cls(
            duration_days,
            allow_repeats=allow_meal_repeats,
            repeat_interval_days=meal_repeat_interval_days,
            existing_usage=existing_usage,
            variation_seed=variation_seed,
        )

    @classmethod
    def from_plan_days(
        cls,
        days: List[Dict[str, Any]],
        *,
        allow_meal_repeats: bool = True,
        meal_repeat_interval_days: int = 4,
        skip_day: Optional[int] = None,
        skip_meal_index: Optional[int] = None,
        variation_seed: Optional[int] = None,
    ) -> "MealVarietyPlanner":
        usage: Dict[str, List[int]] = {}
        duration = len(days)
        for di, day in enumerate(days):
            if not isinstance(day, dict):
                continue
            meals = day.get("meals") or []
            for mi, meal in enumerate(meals):
                if skip_day == di and skip_meal_index == mi:
                    continue
                if not isinstance(meal, dict):
                    continue
                title = meal.get("title")
                if title:
                    usage.setdefault(str(title), []).append(di)
        return cls(
            duration,
            allow_repeats=allow_meal_repeats,
            repeat_interval_days=meal_repeat_interval_days,
            existing_usage=usage,
            variation_seed=variation_seed,
        )

    def pick(
        self,
        pool: List[Dict[str, Any]],
        *,
        meal_type: str,
        day_index: int,
        slot_index: int,
        exclude_titles: Optional[Set[str]] = None,
    ) -> Dict[str, Any]:
        if not pool:
            raise ValueError("empty template pool")

        exclude = exclude_titles or set()
        candidates: List[Dict[str, Any]] = []

        for tpl in pool:
            title = tpl["title"]
            if title in exclude:
                continue
            if self._too_soon(title, day_index) and self._has_alternatives(pool, title, exclude):
                continue
            if self._same_as_previous_day_slot(title, meal_type, day_index) and len(pool) > 1:
                continue
            candidates.append(tpl)

        if not candidates:
            candidates = [t for t in pool if t["title"] not in exclude]
        if not candidates:
            candidates = list(pool)

        self._rng.shuffle(candidates)
        best_idx = 0
        best_score = -1.0
        for idx, tpl in enumerate(candidates):
            score = self._variety_score(tpl["title"], day_index) + self._rng.uniform(0, 5)
            if score > best_score:
                best_score = score
                best_idx = idx

        chosen = candidates[best_idx]
        self._register(chosen["title"], day_index, meal_type)
        return chosen

    def _variety_score(self, title: str, day_index: int) -> float:
        days_used = self._usage.get(title, [])
        if not days_used:
            return 100.0
        last = max(days_used)
        return float(day_index - last)

    def _too_soon(self, title: str, day_index: int) -> bool:
        days_used = self._usage.get(title, [])
        if not days_used:
            return False
        gap = day_index - max(days_used)
        if not self.allow_repeats:
            return gap < self.repeat_gap
        return gap < self.repeat_gap

    def _has_alternatives(
        self,
        pool: List[Dict[str, Any]],
        title: str,
        exclude: Set[str],
    ) -> bool:
        return any(
            t["title"] != title and t["title"] not in exclude for t in pool
        )

    def _same_as_previous_day_slot(
        self, title: str, meal_type: str, day_index: int
    ) -> bool:
        if day_index <= 0:
            return False
        prev_key = f"{day_index - 1}:{meal_type}"
        return self._slot_last.get(prev_key) == title

    def _register(self, title: str, day_index: int, meal_type: str) -> None:
        self._usage.setdefault(title, []).append(day_index)
        self._slot_last[f"{day_index}:{meal_type}"] = title

    def collect_titles_from_plan(
        self, days: List[Dict[str, Any]], *, except_day: int, except_meal: int
    ) -> Set[str]:
        titles: Set[str] = set()
        for di, day in enumerate(days):
            if not isinstance(day, dict):
                continue
            for mi, meal in enumerate(day.get("meals") or []):
                if di == except_day and mi == except_meal:
                    continue
                if isinstance(meal, dict) and meal.get("title"):
                    titles.add(str(meal["title"]))
        return titles
