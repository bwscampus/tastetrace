"""Ported from app/test/time.test.ts and severity.test.ts."""

from datetime import UTC, datetime

from app.deps import is_valid_timezone
from app.domain.catalog import catalog_by_name, custom_symptom_key
from app.domain.rounding import js_round
from app.domain.severity import discomfort_score, intensity_from_severity, severity_from_intensity
from app.domain.time import add_days, day_bounds, local_date, local_time

INSTANT = datetime(2026, 9, 11, 21, 29, tzinfo=UTC)


def test_an_instant_belongs_to_a_different_day_in_each_zone():
    assert local_date(INSTANT, "America/Los_Angeles") == "2026-09-11"
    assert local_date(INSTANT, "Asia/Tokyo") == "2026-09-12"
    assert local_time(INSTANT, "America/Los_Angeles") == "14:29"


def test_day_bounds_span_local_midnight_to_midnight():
    start, end = day_bounds("2026-09-11", "America/Los_Angeles")
    assert start.isoformat() == "2026-09-11T07:00:00+00:00"
    assert end.isoformat() == "2026-09-12T07:00:00+00:00"


def test_add_days_crosses_months_and_years():
    assert add_days("2026-02-28", 1) == "2026-03-01"
    assert add_days("2026-01-01", -1) == "2025-12-31"


def test_timezone_names_are_validated():
    assert is_valid_timezone("America/Los_Angeles") is True
    assert is_valid_timezone("Mars/Olympus") is False
    assert is_valid_timezone(None) is False


def test_rounding_matches_javascript_not_bankers():
    # Python's round() would give 0 and 2 here; every ported formula needs half-up
    assert js_round(0.5) == 1
    assert js_round(2.5) == 3


def test_the_two_symptom_scales_agree():
    assert [severity_from_intensity(i) for i in (1, 2, 3, 4, 5)] == [
        "Mild", "Mild", "Moderate", "Severe", "Severe",
    ]
    for severity in ("Mild", "Moderate", "Severe"):
        assert severity_from_intensity(intensity_from_severity(severity)) == severity
    assert discomfort_score(3) == 6


def test_catalog_lookup_and_custom_keys():
    assert catalog_by_name("acid reflux").key == "acid_reflux"
    assert catalog_by_name("Brain fog") is None
    assert custom_symptom_key(" Brain Fog! ") == "custom:brain-fog"
    assert custom_symptom_key("???") == "custom:symptom"
