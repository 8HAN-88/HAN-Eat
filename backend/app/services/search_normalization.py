"""Shared helpers for user-facing search queries."""
import re
from typing import List


def normalize_search_text(value: str) -> str:
    """Normalize text before token matching without changing user-visible data."""
    return re.sub(r"\s+", " ", (value or "").lower().replace("ё", "е")).strip()


def search_terms(value: str) -> List[str]:
    """Extract stable search tokens from free-form user input."""
    normalized = normalize_search_text(value)
    terms = re.findall(r"[\w]+", normalized, flags=re.UNICODE)
    seen = set()
    result: List[str] = []
    for term in terms:
        term = term.strip("_")
        if not term or term in seen:
            continue
        seen.add(term)
        result.append(term)
    return result


def stable_search_key(value: str) -> str:
    """Canonical key for cache keys and PostgreSQL websearch input."""
    return " ".join(search_terms(value))


def escaped_like_pattern(value: str) -> str:
    """Build a contains-pattern while treating %, _ and \\ as literal chars."""
    escaped = (
        normalize_search_text(value)
        .replace("\\", "\\\\")
        .replace("%", "\\%")
        .replace("_", "\\_")
    )
    return f"%{escaped}%"
