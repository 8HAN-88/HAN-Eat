"""Тесты локализации карточек рецептов."""
from app.services.recipe_localization_service import (
    apply_recipe_localization_to_cards,
    card_needs_localization,
)


def test_card_needs_localization_spoonacular_en_to_ru():
    card = {"title": "Smoked Salmon", "source": "spoonacular"}
    assert card_needs_localization(card, "ru") is True


def test_card_needs_localization_channel_ru_skipped():
    card = {"title": "Суши", "source": "channel"}
    assert card_needs_localization(card, "ru") is False


def test_apply_without_user_sets_requires_ai():
    cards = [
        {
            "id": 1,
            "title": "Pasta",
            "source": "spoonacular",
            "ingredients": ["pasta"],
            "translated_title": "Pasta",
            "translated_ingredients": ["pasta"],
            "steps": [],
        }
    ]
    out, meta = apply_recipe_localization_to_cards(cards, "ru", None, None, full=False)
    assert meta["recipe_translation_requires_ai"] is True
    assert meta["recipe_translation_language"] == "ru"
    assert out[0]["translated_title"] == "Pasta"
