"""Ported from app/test/coverage.test.ts."""

from datetime import UTC, datetime

from app.domain.coverage import compute_coverage
from app.domain.rows import MealRow, SettingsRow

TZ = "America/Los_Angeles"
SETTINGS = SettingsRow(streak_meals_per_day=2, nudge_time="20:30", nudges_enabled=True)

_next_id = iter(range(1, 10_000))


def meal(iso: str, meal_type: str) -> MealRow:
    return MealRow(
        id=next(_next_id),
        name="m",
        meal_type=meal_type,
        timestamp=datetime.fromisoformat(iso).replace(tzinfo=UTC),
    )


def test_slots_take_the_first_meal_and_ignore_snacks():
    meals = [
        meal("2026-09-17T15:15:00", "Breakfast"),  # 08:15 local
        meal("2026-09-17T19:45:00", "Lunch"),
        meal("2026-09-17T18:00:00", "Lunch"),  # earlier, so this one fills the slot
        meal("2026-09-17T23:00:00", "Snack"),
    ]
    coverage = compute_coverage(meals, "2026-09-17", TZ, SETTINGS)

    assert coverage.slots["Breakfast"].logged is True
    assert coverage.slots["Breakfast"].time == "08:15"
    assert coverage.slots["Breakfast"].meal_id == meals[0].id
    assert coverage.slots["Lunch"].time == "11:00"
    assert coverage.slots["Dinner"].logged is False
    assert coverage.logged_count == 2
    assert coverage.percent == 67
    assert len(coverage.week) == 7

    last = coverage.week[6]
    assert (last.date, last.weekday, last.meals, last.slots_logged, last.met_threshold) == (
        "2026-09-17", "Thu", 4, 2, True,
    )
    assert (coverage.week_slots.logged, coverage.week_slots.total) == (2, 21)
    assert (coverage.nudge.time, coverage.nudge.enabled) == ("20:30", True)


def test_an_unfinished_day_does_not_break_the_streak():
    meals = [
        meal("2026-09-15T15:00:00", "Breakfast"), meal("2026-09-15T20:00:00", "Lunch"),
        meal("2026-09-16T15:00:00", "Breakfast"), meal("2026-09-16T20:00:00", "Lunch"),
        meal("2026-09-17T15:00:00", "Breakfast"),  # today: only one so far
    ]

    open_day = compute_coverage(meals, "2026-09-17", TZ, SETTINGS)
    assert open_day.streak.days == 2
    assert open_day.streak.today_counts is False
    assert open_day.streak.rule == "2+ Meals/Day"

    closed = compute_coverage([*meals, meal("2026-09-17T20:00:00", "Lunch")], "2026-09-17", TZ, SETTINGS)
    assert closed.streak.days == 3
    assert closed.streak.today_counts is True

    broken = [m for m in meals if not m.timestamp.isoformat().startswith("2026-09-16")]
    assert compute_coverage(broken, "2026-09-17", TZ, SETTINGS).streak.days == 0


def test_days_are_bucketed_in_the_requested_timezone():
    dinner = [meal("2026-09-18T02:00:00", "Dinner")]  # 7pm on the 17th in Los Angeles
    assert compute_coverage(dinner, "2026-09-17", TZ, SETTINGS).slots["Dinner"].logged is True
    assert compute_coverage(dinner, "2026-09-17", "UTC", SETTINGS).slots["Dinner"].logged is False
