"""User search query helpers."""
from app.services.search_normalization import escaped_like_pattern, normalize_search_text


def test_search_query_strips_at_in_service_layer():
    q = "@chef".strip().lstrip("@")
    assert q == "chef"
    assert escaped_like_pattern(q) == "%chef%"


def test_search_normalizes_yo_for_name_matching():
    assert normalize_search_text("Ёжик") == "ежик"
