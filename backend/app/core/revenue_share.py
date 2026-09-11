"""Чистые доли: только нетто с рекламы и подписки.

От «100% прибыли» сначала вычитаются расходы (остаётся 70% нетто).
Из нетто: реферал всегда 25% (это 17.5 пунктов исходных 100%).
Пользователь получает 50% нетто только с рекламы и только если
включил программу доп. рекламы (35 пунктов исходных 100%).
Подписка пользователю не кэшится. Stars / подарки / TON не входят.
"""

from __future__ import annotations

from typing import Literal

SOURCE_ADS = "ads"
SOURCE_SUBSCRIPTION = "subscription"
ROLE_VIEWER = "viewer"
ROLE_REFERRER = "referrer"

NET_FACTOR_BPS = 7000
REFERRER_OF_NET_BPS = 2500
USER_AD_OF_NET_BPS = 5000
REFERRAL_DAYS = 365
HOLD_DAYS = 14
APPLY_CODE_MAX_AGE_DAYS = 7

IMPRESSION_GROSS_KOPECKS = 20
CLICK_GROSS_KOPECKS = 200


def split_kopecks(
    gross: int,
    *,
    source: Literal["ads", "subscription"],
    extra_ads: bool,
    has_referrer: bool,
) -> dict[str, int]:
    if gross <= 0:
        return {"gross": 0, "net": 0, "user": 0, "referrer": 0, "company": 0}
    net = gross * NET_FACTOR_BPS // 10_000
    user = 0
    if source == SOURCE_ADS and extra_ads:
        user = net * USER_AD_OF_NET_BPS // 10_000
    referrer = net * REFERRER_OF_NET_BPS // 10_000 if has_referrer else 0
    if user + referrer > net:
        referrer = max(0, net - user)
    company = max(0, net - user - referrer)
    return {
        "gross": int(gross),
        "net": int(net),
        "user": int(user),
        "referrer": int(referrer),
        "company": int(company),
    }


def rub_to_kopecks(amount: float) -> int:
    if amount <= 0:
        return 0
    return int(round(float(amount) * 100))
