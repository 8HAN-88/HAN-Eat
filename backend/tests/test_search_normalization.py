from app.services.search_normalization import (
    escaped_like_pattern,
    normalize_search_text,
    search_terms,
    stable_search_key,
)


def test_search_terms_normalize_user_symbols_and_yo():
    assert search_terms("  #Сырный-омлёт @chef  ") == [
        "сырный",
        "омлет",
        "chef",
    ]


def test_search_terms_keep_order_and_drop_duplicates():
    assert search_terms("курица салат курица") == ["курица", "салат"]


def test_stable_search_key_is_cache_safe():
    assert stable_search_key("#ЗОЖ   быстрый_ужин") == "зож быстрый_ужин"


def test_escaped_like_pattern_treats_wildcards_as_literals():
    assert escaped_like_pattern(r"50%_ужин\план") == r"%50\%\_ужин\\план%"


def test_normalize_search_text_keeps_plain_text_comparable():
    assert normalize_search_text("Ёжик   в   Тумане") == "ежик в тумане"
