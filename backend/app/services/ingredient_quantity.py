"""Разбор количества в строках ингредиентов и объединение для списка покупок."""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

# (regex, unit_key, display_unit)
_QUANTITY_PATTERNS: List[Tuple[str, str, str]] = [
    (r"(\d+(?:[.,]\d+)?)\s*(?:кг|kg)\b", "kg", "кг"),
    (r"(\d+(?:[.,]\d+)?)\s*(?:г|гр|грамм\w*)\b", "g", "г"),
    (r"(\d+(?:[.,]\d+)?)\s*(?:мл|ml)\b", "ml", "мл"),
    (r"(\d+(?:[.,]\d+)?)\s*(?:л|l)\b", "l", "л"),
    (r"(\d+)\s*(?:шт\.?|штук\w*)\b", "pcs", "шт"),
    (r"(\d+)\s*(?:ст\.?\s*л\.?|столов\w*\s*ложк\w*)\b", "tbsp", "ст. л."),
    (r"(\d+)\s*(?:ч\.?\s*л\.?|чайн\w*\s*ложк\w*)\b", "tsp", "ч. л."),
    (r"(\d+)\s*(?:зубч\.?|зубчик\w*)\b", "clove", "зуб."),
    (r"(\d+)\s*(?:пучок|пучк\w*)\b", "bunch", "пучок"),
    (r"(\d+)\s*(?:стак\.?|стакан\w*)\b", "cup", "стак."),
]


@dataclass
class ParsedIngredient:
    name: str
    amount: Optional[float] = None
    unit: Optional[str] = None  # g, ml, pcs, ...
    portions: int = 1

    @property
    def merge_key(self) -> str:
        base = _normalize_name(self.name)
        if self.unit:
            return f"{base}|{self.unit}"
        return base

    def scaled(self, factor: float) -> "ParsedIngredient":
        if self.amount is None or factor == 1:
            return self
        return ParsedIngredient(
            name=self.name,
            amount=round(self.amount * factor, 1),
            unit=self.unit,
        )

    def display_quantity(self) -> Optional[str]:
        if self.amount is None or not self.unit:
            if self.portions > 1:
                return f"×{self.portions} порц."
            return None
        val = self.amount
        if val == int(val):
            val_s = str(int(val))
        else:
            val_s = f"{val:g}".replace(".", ",")
        unit_labels = {
            "g": "г",
            "kg": "кг",
            "ml": "мл",
            "l": "л",
            "pcs": "шт",
            "tbsp": "ст. л.",
            "tsp": "ч. л.",
            "clove": "зуб.",
            "bunch": "пучок",
            "cup": "стак.",
        }
        return f"{val_s} {unit_labels.get(self.unit, self.unit)}"


def _normalize_name(name: str) -> str:
    s = name.strip().lower()
    s = re.sub(r"\s+", " ", s)
    return s


def parse_ingredient_line(line: str) -> ParsedIngredient:
    """«куриная грудка 200 г» → name + amount."""
    raw = line.strip()
    if not raw:
        return ParsedIngredient(name="")

    working = raw
    amount: Optional[float] = None
    unit: Optional[str] = None

    for pattern, unit_key, _disp in _QUANTITY_PATTERNS:
        m = re.search(pattern, working, flags=re.IGNORECASE)
        if not m:
            continue
        amount = float(m.group(1).replace(",", "."))
        unit = unit_key
        if unit_key == "kg":
            amount *= 1000
            unit = "g"
        if unit_key == "l":
            amount *= 1000
            unit = "ml"
        working = (working[: m.start()] + working[m.end() :]).strip(" ,-–—")
        break

    name = re.sub(r"\s+", " ", working).strip(" ,-–—")
    if not name:
        name = raw
    return ParsedIngredient(name=name, amount=amount, unit=unit)


def merge_ingredient_lines(
    lines: List[str],
    *,
    portions: int = 1,
) -> Dict[str, ParsedIngredient]:
    """Объединить ингредиенты плана: суммировать граммы/штуки по продукту."""
    merged: Dict[str, ParsedIngredient] = {}
    factor = max(1, portions)

    for line in lines:
        parsed = parse_ingredient_line(line)
        if parsed.amount is not None and parsed.unit:
            parsed = parsed.scaled(factor)
        else:
            parsed = ParsedIngredient(
                name=parsed.name,
                amount=None,
                unit=None,
                portions=factor,
            )
        key = parsed.merge_key
        if not parsed.name:
            continue
        if key not in merged:
            merged[key] = parsed
            continue
        prev = merged[key]
        if (
            prev.amount is not None
            and parsed.amount is not None
            and prev.unit == parsed.unit
        ):
            merged[key] = ParsedIngredient(
                name=prev.name,
                amount=prev.amount + parsed.amount,
                unit=prev.unit,
                portions=prev.portions,
            )
        elif parsed.amount is None and prev.amount is None:
            merged[key] = ParsedIngredient(
                name=prev.name,
                amount=None,
                unit=None,
                portions=prev.portions + parsed.portions,
            )
        else:
            # разные единицы — оставляем отдельной строкой с суффиксом
            alt_key = f"{key}#{len(merged)}"
            merged[alt_key] = parsed

    return merged
