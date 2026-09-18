"""How completely a day was logged, and the streak that comes from it."""

from dataclasses import dataclass, field

from app.domain.rounding import js_round
from app.domain.rows import MealRow, SettingsRow
from app.domain.time import add_days, local_date, local_time, weekday_label

# Snacks are logged but never count toward coverage
COVERAGE_SLOTS: tuple[str, ...] = ("Breakfast", "Lunch", "Dinner")


@dataclass
class SlotStatus:
    logged: bool
    meal_id: int | None = None
    time: str | None = None


@dataclass
class DayCoverage:
    date: str
    weekday: str
    meals: int
    slots_logged: int
    met_threshold: bool


@dataclass
class Streak:
    days: int
    threshold: int
    rule: str
    today_counts: bool


@dataclass
class SlotTally:
    logged: int
    total: int


@dataclass
class WeekSlots:
    logged: int
    total: int
    by_slot: dict[str, SlotTally]


@dataclass
class Nudge:
    time: str
    enabled: bool


@dataclass
class Coverage:
    date: str
    slots: dict[str, SlotStatus]
    logged_count: int
    slot_total: int
    percent: int
    streak: Streak
    week: list[DayCoverage]
    week_slots: WeekSlots
    nudge: Nudge


@dataclass
class _Day:
    meals: list[MealRow] = field(default_factory=list)
    slots: dict[str, MealRow] = field(default_factory=dict)


def _group_by_day(meals: list[MealRow], tz: str) -> dict[str, _Day]:
    days: dict[str, _Day] = {}
    for meal in meals:
        day = days.setdefault(local_date(meal.timestamp, tz), _Day())
        day.meals.append(meal)
        if meal.meal_type in COVERAGE_SLOTS:
            current = day.slots.get(meal.meal_type)
            # The first meal of a slot is the one that fills it
            if current is None or meal.timestamp < current.timestamp:
                day.slots[meal.meal_type] = meal
    return days


def compute_coverage(
    meals: list[MealRow], date: str, tz: str, settings: SettingsRow
) -> Coverage:
    """Coverage for one day, plus the trailing week and the current streak."""
    days = _group_by_day(meals, tz)
    threshold = settings.streak_meals_per_day
    today = days.get(date)

    slots: dict[str, SlotStatus] = {}
    for slot in COVERAGE_SLOTS:
        meal = today.slots.get(slot) if today else None
        slots[slot] = (
            SlotStatus(logged=True, meal_id=meal.id, time=local_time(meal.timestamp, tz))
            if meal
            else SlotStatus(logged=False)
        )
    logged_count = sum(1 for slot in COVERAGE_SLOTS if slots[slot].logged)

    week: list[DayCoverage] = []
    for offset in range(6, -1, -1):
        day_date = add_days(date, -offset)
        day = days.get(day_date)
        meal_count = len(day.meals) if day else 0
        week.append(
            DayCoverage(
                date=day_date,
                weekday=weekday_label(day_date),
                meals=meal_count,
                slots_logged=len(day.slots) if day else 0,
                met_threshold=meal_count >= threshold,
            )
        )

    # A day still in progress shouldn't break a streak, so start from
    # yesterday when today hasn't met the threshold yet.
    today_counts = (len(today.meals) if today else 0) >= threshold
    cursor = date if today_counts else add_days(date, -1)
    streak_days = 0
    while len(days.get(cursor, _Day()).meals) >= threshold:
        streak_days += 1
        cursor = add_days(cursor, -1)

    by_slot = {
        slot: SlotTally(
            logged=sum(1 for day in week if slot in days.get(day.date, _Day()).slots),
            total=7,
        )
        for slot in COVERAGE_SLOTS
    }

    return Coverage(
        date=date,
        slots=slots,
        logged_count=logged_count,
        slot_total=len(COVERAGE_SLOTS),
        percent=js_round(logged_count / len(COVERAGE_SLOTS) * 100),
        streak=Streak(
            days=streak_days,
            threshold=threshold,
            rule=f"{threshold}+ Meals/Day",
            today_counts=today_counts,
        ),
        week=week,
        week_slots=WeekSlots(
            logged=sum(tally.logged for tally in by_slot.values()),
            total=len(COVERAGE_SLOTS) * 7,
            by_slot=by_slot,
        ),
        nudge=Nudge(time=settings.nudge_time, enabled=settings.nudges_enabled),
    )
