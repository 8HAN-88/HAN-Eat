from datetime import datetime, timezone

from app.core.time_iso import parse_search_bound, utc_iso


def test_naive_utc_gains_z():
    assert utc_iso(datetime(2026, 11, 8, 12, 14)) == "2026-11-08T12:14:00Z"


def test_aware_utc_uses_z():
    value = datetime(2026, 11, 8, 12, 14, tzinfo=timezone.utc)
    assert utc_iso(value) == "2026-11-08T12:14:00Z"


def test_none_stays_none():
    assert utc_iso(None) is None


def test_date_only_search_bound_stays_a_utc_day():
    assert parse_search_bound("2026-11-09") == datetime(2026, 11, 9)
    assert parse_search_bound("2026-11-09", end_of_day=True) == datetime(
        2026, 11, 9, 23, 59, 59
    )
    assert parse_search_bound(None) is None
    assert parse_search_bound("  ") is None


def test_offset_search_bound_is_naive_utc():
    # Moscow midnight on the 9th is 21:00 UTC on the 8th.
    assert parse_search_bound("2026-11-09T00:00:00+03:00") == datetime(
        2026, 11, 8, 21, 0, 0
    )
    assert parse_search_bound(
        "2026-11-09T23:59:59.999999+03:00",
        end_of_day=True,
    ) == datetime(2026, 11, 9, 20, 59, 59, 999999)


def test_zulu_search_bound():
    assert parse_search_bound("2026-11-08T21:00:00.000Z") == datetime(
        2026, 11, 8, 21, 0, 0
    )
