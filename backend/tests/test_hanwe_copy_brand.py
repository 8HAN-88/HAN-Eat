"""User-facing catalog / API text must not name other products."""

from app.core.flex_catalog import DEFAULT_BLOCKS, DEFAULT_FEATURES

_FORBIDDEN = (
    "Telegram",
    "Instagram",
    "BotFather",
    "WhatsApp",
    "Fragment",
    "TikTok",
    "TON",
)


def _assert_clean(label: str, text: str) -> None:
    for word in _FORBIDDEN:
        assert word not in text, f"{label} mentions {word!r}: {text}"


def test_flex_blocks_have_no_foreign_brands() -> None:
    titles = [str(block.get("title") or "") for block in DEFAULT_BLOCKS]
    assert "Чат++" in titles
    assert "Telegram+" not in titles
    for block in DEFAULT_BLOCKS:
        _assert_clean(f"block {block.get('key')}", str(block.get("title") or ""))


def test_flex_features_have_no_foreign_brands() -> None:
    for feature in DEFAULT_FEATURES:
        slug = feature.get("slug")
        _assert_clean(f"title {slug}", str(feature.get("title") or ""))
        _assert_clean(f"description {slug}", str(feature.get("description") or ""))
