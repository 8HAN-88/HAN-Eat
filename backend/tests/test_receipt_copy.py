from app.core.receipt_copy import product_label, receipt_item_description
from app.services.flex_subscription_service import level_from_price, price_for_level


def test_receipt_names_use_flex_levels() -> None:
    assert product_label("ai") == "HanWe · уровень 9"
    assert product_label("creator") == "HanWe · уровень 16"
    assert product_label("pro") == "HanWe · уровень 18"
    assert product_label("flex") == "HanWe"
    assert product_label("flex", level=12) == "HanWe · уровень 12"


def test_receipt_item_description_is_russian() -> None:
    assert receipt_item_description("pro") == "Подписка HanWe · уровень 18 (1 мес.)"
    assert receipt_item_description("flex", level=7) == (
        "Подписка HanWe · уровень 7 (1 мес.)"
    )
    assert "HanWe Pro" not in receipt_item_description("pro")


def test_flex_level_from_price() -> None:
    assert level_from_price(price_for_level(1)) == 1
    assert level_from_price(price_for_level(16)) == 16
    assert level_from_price(price_for_level(79)) == 79
    assert level_from_price(0) is None
    assert level_from_price("x") is None
