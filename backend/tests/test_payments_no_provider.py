"""Релиз без ЮKassa: каталог цен и checkout."""
from unittest.mock import patch

from app.services.country_service import CountryService


def test_ru_provider_none_when_yookassa_disabled():
    with patch("app.services.ru_payment_provider.settings.TBANK_ENABLED", False):
        with patch("app.services.ru_payment_provider.settings.YOOKASSA_ENABLED", False):
            assert CountryService.get_payment_provider_for_country("RU") == "none"

