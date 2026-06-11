"""Тесты начисления AI scan кредитов."""
from datetime import datetime, timedelta
from unittest.mock import MagicMock, patch

import pytest

from app.services.ai_scan_credits_service import (
    FREE_CAP,
    FREE_DAILY,
    FREE_START,
    PLUS_CAP,
    PLUS_DAILY,
    PLUS_START,
    AiScanCreditsService,
)


def _user(credits=5, last_at=None, created_at=None):
    u = MagicMock()
    u.id = 42
    u.scan_credits = credits
    u.last_scan_credit_at = last_at
    u.created_at = created_at or datetime.utcnow()
    u.subscription_type = "free"
    return u


@patch.object(AiScanCreditsService, "is_plus", return_value=False)
def test_free_accrue_after_one_day(mock_plus):
    db = MagicMock()
    user = _user(credits=FREE_START, last_at=datetime.utcnow() - timedelta(days=2))
    db.query.return_value.filter.return_value.first.return_value = user
    svc = AiScanCreditsService(db)
    svc.accrue_if_needed(user)
    assert user.scan_credits == min(FREE_CAP, FREE_START + 2 * FREE_DAILY)


@patch.object(AiScanCreditsService, "is_plus", return_value=True)
def test_on_ai_access_activated_grants_20(mock_plus):
    db = MagicMock()
    user = _user(credits=0)
    db.query.return_value.filter.return_value.first.return_value = user
    svc = AiScanCreditsService(db)
    svc.on_ai_access_activated(42)
    assert user.scan_credits == PLUS_START
    db.commit.assert_called_once()


@patch.object(AiScanCreditsService, "is_plus", return_value=False)
def test_soft_warning_at_one_credit(mock_plus):
    db = MagicMock()
    user = _user(credits=1)
    svc = AiScanCreditsService(db)
    meta = svc.status_meta(user)
    assert meta["soft_warning"] is True
    assert meta["can_scan"] is True


@patch.object(AiScanCreditsService, "is_plus", return_value=False)
def test_refund_reserved_scan_caps_free_balance(mock_plus):
    db = MagicMock()
    user = _user(credits=FREE_CAP)
    db.query.return_value.filter.return_value.first.return_value = user
    svc = AiScanCreditsService(db)
    svc.refund_reserved_scan(42)
    assert user.scan_credits == FREE_CAP
    db.commit.assert_called_once()


@patch.object(AiScanCreditsService, "is_plus", return_value=True)
def test_refund_reserved_scan_restores_one_plus_credit(mock_plus):
    db = MagicMock()
    user = _user(credits=12)
    db.query.return_value.filter.return_value.first.return_value = user
    svc = AiScanCreditsService(db)
    svc.refund_reserved_scan(42)
    assert user.scan_credits == 13
    db.commit.assert_called_once()
