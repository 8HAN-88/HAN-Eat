from datetime import datetime, timezone

from app.core.time_iso import utc_iso


def test_naive_utc_gains_z():
    assert utc_iso(datetime(2026, 11, 8, 12, 14)) == "2026-11-08T12:14:00Z"


def test_aware_utc_uses_z():
    value = datetime(2026, 11, 8, 12, 14, tzinfo=timezone.utc)
    assert utc_iso(value) == "2026-11-08T12:14:00Z"


def test_none_stays_none():
    assert utc_iso(None) is None
