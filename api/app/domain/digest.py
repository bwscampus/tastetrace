"""The weekly digest: how the week went, and per-symptom detail."""

import math
from dataclasses import dataclass, field
from typing import Literal

from app.domain.catalog import catalog_by_key, catalog_by_name
from app.domain.coverage import COVERAGE_SLOTS
from app.domain.flares import cluster_flares, intensity_of, onset_hours
from app.domain.rounding import js_round, round1, round2
from app.domain.rows import CorrelationRow, MealRow, SettingsRow, SymptomRow
from app.domain.severity import discomfort_score
from app.domain.time import add_days, days_between, local_date, week_dates, weekday_label

Level = Literal["zero", "moderate", "high"]
Trend = Literal["up", "same", "down"]

# Walking the baseline day by day is bounded so a stray old entry can't hang a request
MAX_BASELINE_DAYS = 3660


@dataclass
class DayTrend:
    date: str
    weekday: str
    index: float
    occurrences: int
    max_intensity: int
    level: Level


@dataclass
class SymptomCard:
    name: str
    catalog_key: str | None
    emoji: str | None
    occurrences: int
    share_of_week: float
    avg_severity10: float
    avg_duration_minutes: int | None
    peak_day: str | None
    vs_baseline: Trend
    top_triggers: list[str]


@dataclass
class OnsetWindows:
    under1h: int = 0
    from1to3h: int = 0
    over3h: int = 0
    unmatched: int = 0


@dataclass
class Trends:
    index: float
    baseline_index: float
    delta_vs_baseline_percent: int
    previous_week_index: float
    change_vs_previous_percent: int
    occurrences: int
    flares: int
    discomfort_free_days: int
    severe_days: int
    severe_peak_day: str | None
    meal_log_depth: float
    data_completeness: Literal["complete", "partial", "empty"]
    days: list[DayTrend]


@dataclass
class SymptomsSection:
    total: int
    baseline_per_week: float
    vs_baseline: Trend
    distinct: int
    distribution: list[dict]
    cards: list[SymptomCard]
    onset_windows: OnsetWindows


@dataclass
class WeeklyDigest:
    week_start: str
    week_end: str
    previous_week_start: str
    has_next_week: bool
    trends: Trends
    symptoms: SymptomsSection


def day_index(symptoms: list[SymptomRow]) -> float:
    """A day's discomfort on the 0-10 scale: its worst symptom, doubled."""
    return 0 if not symptoms else discomfort_score(max(intensity_of(s) for s in symptoms))


def level_for(index: float) -> Level:
    if index == 0:
        return "zero"
    return "high" if index >= 5 else "moderate"


def compare(value: float, baseline: float) -> Trend:
    if baseline == 0:
        return "same" if value == 0 else "up"
    ratio = value / baseline
    if ratio > 1.2:
        return "up"
    if ratio < 0.8:
        return "down"
    return "same"


def _percent_change(value: float, reference: float) -> int:
    return js_round((value - reference) / reference * 100) if reference > 0 else 0


def compute_weekly_digest(
    meals: list[MealRow],
    symptoms: list[SymptomRow],
    correlations: list[CorrelationRow],
    week_start: str,
    tz: str,
    settings: SettingsRow,
    today: str,
) -> WeeklyDigest:
    """`meals` and `symptoms` are the user's whole history: the week is scored
    against everything logged so far."""
    dates = week_dates(week_start)
    week_end = dates[6]

    symptoms_by_day: dict[str, list[SymptomRow]] = {}
    for symptom in symptoms:
        symptoms_by_day.setdefault(local_date(symptom.timestamp, tz), []).append(symptom)
    meals_by_day: dict[str, list[MealRow]] = {}
    for meal in meals:
        meals_by_day.setdefault(local_date(meal.timestamp, tz), []).append(meal)

    days = [
        DayTrend(
            date=date,
            weekday=weekday_label(date),
            index=day_index(symptoms_by_day.get(date, [])),
            occurrences=len(symptoms_by_day.get(date, [])),
            max_intensity=max(
                (intensity_of(s) for s in symptoms_by_day.get(date, [])), default=0
            ),
            level=level_for(day_index(symptoms_by_day.get(date, []))),
        )
        for date in dates
    ]
    # Always over seven days, so a partly-logged week reads as calmer, not worse
    week_index = sum(day.index for day in days) / 7

    logged_dates = sorted(set(symptoms_by_day) | set(meals_by_day))
    baseline_index = 0.0
    if logged_dates:
        cursor, last = logged_dates[0], max(today, week_end)
        total = count = 0
        while cursor <= last and count < MAX_BASELINE_DAYS:
            total += day_index(symptoms_by_day.get(cursor, []))
            count += 1
            cursor = add_days(cursor, 1)
        baseline_index = total / count if count else 0.0

    previous_week_start = add_days(week_start, -7)
    previous_index = sum(
        day_index(symptoms_by_day.get(date, [])) for date in week_dates(previous_week_start)
    ) / 7

    week_symptoms = [s for date in dates for s in symptoms_by_day.get(date, [])]
    peak = max(days, key=lambda d: d.index) if days else None

    slots_logged = sum(
        len({m.meal_type for m in meals_by_day.get(date, [])} & set(COVERAGE_SLOTS))
        for date in dates
    )
    logged_days = sum(
        1 for date in dates if meals_by_day.get(date) or symptoms_by_day.get(date)
    )
    elapsed_days = sum(1 for date in dates if date <= today)
    completeness = (
        "empty" if logged_days == 0 else "complete" if logged_days >= elapsed_days else "partial"
    )

    by_name: dict[str, list[SymptomRow]] = {}
    for symptom in week_symptoms:
        by_name.setdefault(symptom.name, []).append(symptom)

    history_weeks = max(
        1,
        math.ceil((days_between(logged_dates[0], today) + 1) / 7) if logged_dates else 1,
    )
    history_counts: dict[str, int] = {}
    for symptom in symptoms:
        history_counts[symptom.name] = history_counts.get(symptom.name, 0) + 1

    cards: list[SymptomCard] = []
    for name, entries in by_name.items():
        catalog = catalog_by_key(entries[0].catalog_key) or catalog_by_name(name)
        durations = [s.duration_minutes for s in entries if s.duration_minutes is not None]
        per_day: dict[str, int] = {}
        for symptom in entries:
            date = local_date(symptom.timestamp, tz)
            per_day[date] = per_day.get(date, 0) + 1
        peak_day = min(
            sorted(per_day), key=lambda date: -per_day[date], default=None
        ) if per_day else None
        cards.append(
            SymptomCard(
                name=name,
                catalog_key=entries[0].catalog_key or (catalog.key if catalog else None),
                emoji=catalog.emoji if catalog else None,
                occurrences=len(entries),
                share_of_week=round1(len(entries) / len(week_symptoms) * 100) / 100,
                avg_severity10=round1(
                    sum(discomfort_score(intensity_of(s)) for s in entries) / len(entries)
                ),
                avg_duration_minutes=js_round(sum(durations) / len(durations)) if durations else None,
                peak_day=peak_day,
                vs_baseline=compare(len(entries), history_counts.get(name, 0) / history_weeks),
                top_triggers=[
                    row.food_name
                    for row in sorted(
                        (
                            r for r in correlations
                            if r.symptom_name == name and r.dimension == "ingredient"
                        ),
                        key=lambda r: -r.confidence,
                    )
                ][:3],
            )
        )
    cards.sort(key=lambda c: (-c.occurrences, c.name.casefold(), c.name))

    windows = OnsetWindows()
    for symptom in week_symptoms:
        hours = onset_hours(meals, symptom.timestamp, settings.correlation_window_hours)
        if hours is None:
            windows.unmatched += 1
        elif hours < 1:
            windows.under1h += 1
        elif hours <= 3:
            windows.from1to3h += 1
        else:
            windows.over3h += 1

    baseline_per_week = len(symptoms) / history_weeks
    return WeeklyDigest(
        week_start=week_start,
        week_end=week_end,
        previous_week_start=previous_week_start,
        has_next_week=add_days(week_start, 7) <= today,
        trends=Trends(
            index=round1(week_index),
            baseline_index=round1(baseline_index),
            delta_vs_baseline_percent=_percent_change(week_index, baseline_index),
            previous_week_index=round1(previous_index),
            change_vs_previous_percent=_percent_change(week_index, previous_index),
            occurrences=len(week_symptoms),
            flares=len(cluster_flares(week_symptoms)),
            discomfort_free_days=sum(1 for day in days if day.index == 0),
            severe_days=sum(1 for day in days if day.level == "high"),
            severe_peak_day=peak.date if peak and peak.index > 0 else None,
            meal_log_depth=round2(slots_logged / 21),
            data_completeness=completeness,
            days=days,
        ),
        symptoms=SymptomsSection(
            total=len(week_symptoms),
            baseline_per_week=round1(baseline_per_week),
            vs_baseline=compare(len(week_symptoms), baseline_per_week),
            distinct=len(by_name),
            distribution=[
                {
                    # Hand-built payload, so the client's spelling is used directly
                    "name": card.name,
                    "catalogKey": card.catalog_key,
                    "count": card.occurrences,
                    "share": card.share_of_week,
                }
                for card in cards
            ],
            cards=cards,
            onset_windows=windows,
        ),
    )
