"""Live location encode/update/stop helpers."""
from datetime import datetime, timedelta, timezone

import pytest

from app.services import chat_location_service as loc


def test_build_and_parse_live_location():
    content = loc.build_live_location_content(
        latitude=55.75,
        longitude=37.61,
        period_seconds=900,
        now=datetime(2026, 8, 6, 12, 0, tzinfo=timezone.utc),
    )
    parsed = loc.parse_location_content(content)
    assert parsed is not None
    assert parsed["is_live"] is True
    assert parsed["period_seconds"] == 900
    assert parsed["stopped"] is False
    assert abs(parsed["latitude"] - 55.75) < 1e-6
    assert loc.is_live_active(
        parsed,
        now=datetime(2026, 8, 6, 12, 5, tzinfo=timezone.utc),
    )
    assert not loc.is_live_active(
        parsed,
        now=datetime(2026, 8, 6, 12, 20, tzinfo=timezone.utc),
    )


def test_invalid_period_rejected():
    with pytest.raises(ValueError, match="invalid_live_period"):
        loc.build_live_location_content(
            latitude=1,
            longitude=2,
            period_seconds=123,
        )


def test_update_and_rate_limit():
    start = datetime(2026, 8, 6, 12, 0, tzinfo=timezone.utc)
    content = loc.build_live_location_content(
        latitude=10,
        longitude=20,
        period_seconds=3600,
        now=start,
    )
    with pytest.raises(ValueError, match="live_location_rate_limited"):
        loc.update_live_location_content(
            content,
            latitude=10.1,
            longitude=20.1,
            now=start + timedelta(seconds=5),
        )

    updated = loc.update_live_location_content(
        content,
        latitude=10.2,
        longitude=20.2,
        now=start + timedelta(seconds=20),
    )
    parsed = loc.parse_location_content(updated)
    assert abs(parsed["latitude"] - 10.2) < 1e-6
    assert parsed["stopped"] is False


def test_stop_live_location():
    content = loc.build_live_location_content(
        latitude=1,
        longitude=2,
        period_seconds=900,
        now=datetime(2026, 8, 6, 12, 0, tzinfo=timezone.utc),
    )
    stopped = loc.stop_live_location_content(content)
    parsed = loc.parse_location_content(stopped)
    assert parsed["stopped"] is True
    assert not loc.is_live_active(
        parsed,
        now=datetime(2026, 8, 6, 12, 1, tzinfo=timezone.utc),
    )


def test_static_location_still_parses():
    content = loc.encode_location_content(latitude=1.5, longitude=2.5, label="Home")
    parsed = loc.parse_location_content(content)
    assert parsed is not None
    assert parsed["is_live"] is False
    assert parsed["label"] == "Home"
