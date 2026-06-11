"""
Страна происхождения блюда в body рецепта (посты каналов и профиля).
"""
from __future__ import annotations

import re
from typing import Any, Dict, Optional, Tuple

_ISO2 = re.compile(r"^[A-Za-z]{2}$")

# Код -> русское название (основные кухни; неполный список — клиент может прислать name)
_COUNTRY_NAMES_RU: Dict[str, str] = {
    "RU": "Россия",
    "IT": "Италия",
    "FR": "Франция",
    "ES": "Испания",
    "DE": "Германия",
    "GR": "Греция",
    "TR": "Турция",
    "GE": "Грузия",
    "AM": "Армения",
    "AZ": "Азербайджан",
    "UA": "Украина",
    "BY": "Беларусь",
    "KZ": "Казахстан",
    "UZ": "Узбекистан",
    "CN": "Китай",
    "JP": "Япония",
    "KR": "Корея",
    "TH": "Таиланд",
    "VN": "Вьетнам",
    "IN": "Индия",
    "US": "США",
    "MX": "Мексика",
    "BR": "Бразилия",
    "AR": "Аргентина",
    "GB": "Великобритания",
    "IL": "Израиль",
    "LB": "Ливан",
    "MA": "Марокко",
    "EG": "Египет",
    "CA": "Канада",
    "AU": "Австралия",
    "PL": "Польша",
    "PT": "Португалия",
    "NL": "Нидерланды",
    "SE": "Швеция",
    "NO": "Норвегия",
    "FI": "Финляндия",
    "DK": "Дания",
    "AT": "Австрия",
    "CH": "Швейцария",
    "CZ": "Чехия",
    "HU": "Венгрия",
    "RO": "Румыния",
    "BG": "Болгария",
    "RS": "Сербия",
    "MD": "Молдова",
    "LT": "Литва",
    "LV": "Латвия",
    "EE": "Эстония",
    "IE": "Ирландия",
    "CY": "Кипр",
    "AE": "ОАЭ",
    "SA": "Саудовская Аравия",
    "IR": "Иран",
    "PK": "Пакистан",
    "ID": "Индонезия",
    "MY": "Малайзия",
    "SG": "Сингапур",
    "PH": "Филиппины",
    "MN": "Монголия",
    "KG": "Кыргызстан",
    "TJ": "Таджикистан",
    "TM": "Туркменистан",
    "ZA": "ЮАР",
    "ET": "Эфиопия",
    "CU": "Куба",
    "PE": "Перу",
    "CO": "Колумбия",
    "CL": "Чили",
    "NZ": "Новая Зеландия",
    "IS": "Исландия",
    "HR": "Хорватия",
    "SI": "Словения",
    "SK": "Словакия",
    "BA": "Босния и Герцеговина",
    "MK": "Северная Македония",
    "AL": "Албания",
    "ME": "Черногория",
}


def normalize_origin_country_code(code: Optional[str]) -> Optional[str]:
    if not code or not str(code).strip():
        return None
    upper = str(code).strip().upper()
    if not _ISO2.match(upper):
        return None
    return upper


def resolve_origin_country_name(
    code: Optional[str], explicit_name: Optional[str] = None
) -> Optional[str]:
    if explicit_name and str(explicit_name).strip():
        return str(explicit_name).strip()[:80]
    norm = normalize_origin_country_code(code)
    if not norm:
        return None
    return _COUNTRY_NAMES_RU.get(norm)


def apply_origin_country_to_recipe_body(
    body: Dict[str, Any],
    *,
    origin_country_code: Optional[str] = None,
    origin_country_name: Optional[str] = None,
    clear_if_empty: bool = False,
) -> None:
    """Записать или удалить поля страны в body рецепта."""
    code = normalize_origin_country_code(origin_country_code)
    if code is None:
        if clear_if_empty or origin_country_code == "":
            body.pop("origin_country_code", None)
            body.pop("origin_country_name", None)
        return
    name = resolve_origin_country_name(code, origin_country_name)
    body["origin_country_code"] = code
    if name:
        body["origin_country_name"] = name


def origin_country_from_body(body: Optional[Dict[str, Any]]) -> Tuple[Optional[str], Optional[str]]:
    if not body:
        return None, None
    code = body.get("origin_country_code")
    name = body.get("origin_country_name")
    norm = normalize_origin_country_code(code if isinstance(code, str) else None)
    resolved_name = resolve_origin_country_name(
        norm, name if isinstance(name, str) else None
    )
    return norm, resolved_name


def origin_country_fields_for_card(body: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    code, name = origin_country_from_body(body)
    if not code:
        return {}
    out: Dict[str, Any] = {"origin_country_code": code}
    if name:
        out["origin_country_name"] = name
    return out
