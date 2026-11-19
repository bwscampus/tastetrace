"""Which ingredients kept showing up before this week's flares."""

from dataclasses import dataclass, field
from datetime import datetime

from app.domain.correlations import usually_fine_items
from app.domain.flares import Flare, cluster_flares, hours_between, meals_before
from app.domain.foods import meal_items, normalize_item
from app.domain.rounding import round1, round2
from app.domain.rows import CorrelationRow, MealRow, SymptomRow
from app.domain.time import local_date, week_dates

ALL_SYMPTOMS = "All Symptoms"
TOP_SUSPECTS = 5
# Fewest separate days a food must come before a symptom to be called a
# suspect; a single day is one meal and one stomachache, not a pattern
MIN_PATTERN_DAYS = 2


@dataclass
class SuspectPair:
    meal_id: int
    meal_name: str
    meal_at: datetime
    flare_at: datetime
    symptoms: list[str]
    onset_hours: float


@dataclass
class Suspect:
    name: str
    flares_with_ingredient: int
    flares_total: int
    share: float
    avg_onset_hours: float | None
    times_logged_this_week: int
    exposures_all_time: int
    confidence: int
    on_watchlist: bool
    # Separate days it came before a symptom, this week or earlier
    days_with_symptoms: int
    recent_pairs: list[SuspectPair]


@dataclass
class TimingWindow:
    flares: int = 0
    top_ingredients: list[str] = field(default_factory=list)


@dataclass
class SuspectsDigest:
    week_start: str
    week_end: str
    window_hours: int
    flares: int
    meals_evaluated: int
    lead_suspect: str | None
    symptom_filters: list[dict]
    ingredients: list[Suspect]
    timing_windows: dict[str, TimingWindow]


@dataclass
class _Entry:
    display: str
    hits: list[tuple[Flare, MealRow, float]] = field(default_factory=list)
    flares: set = field(default_factory=set)
    days: set = field(default_factory=set)


def compute_suspects(
    meals: list[MealRow],
    symptoms: list[SymptomRow],
    correlations: list[CorrelationRow],
    watchlist: list[str],
    week_start: str,
    tz: str,
    window_hours: int,
    symptom_filter: str | None = None,
    min_days: int = MIN_PATTERN_DAYS,
) -> SuspectsDigest:
    dates = set(week_dates(week_start))
    week_symptoms = [s for s in symptoms if local_date(s.timestamp, tz) in dates]
    all_flares = cluster_flares(week_symptoms)

    symptom_filters = [{"name": ALL_SYMPTOMS, "count": len(all_flares)}]
    for name in sorted({s.name for s in week_symptoms}):
        symptom_filters.append(
            {"name": name, "count": sum(1 for f in all_flares if name in f.names)}
        )

    def wanted(flare: Flare) -> bool:
        return not symptom_filter or symptom_filter in flare.names

    flares = [f for f in all_flares if wanted(f)]
    week_flare_ids = {id(f) for f in flares}
    watched = {normalize_item(item) for item in watchlist}

    # The whole history up to the end of this week, so a food that came
    # before a symptom once can be checked against every other day logged
    week_end = week_dates(week_start)[6]
    earlier_symptoms = [
        s for s in symptoms
        if local_date(s.timestamp, tz) <= week_end and local_date(s.timestamp, tz) not in dates
    ]
    history_flares = [
        f for f in cluster_flares(earlier_symptoms) if wanted(f)
    ] + flares

    entries: dict[str, _Entry] = {}
    evaluated: set[int] = set()
    for flare in history_flares:
        in_week = id(flare) in week_flare_ids
        for meal in meals_before(meals, flare.start, window_hours):
            if in_week:
                evaluated.add(meal.id)
            onset = hours_between(meal.timestamp, flare.start)
            for item in meal_items(meal):
                if item.dimension != "ingredient":
                    continue
                entry = entries.setdefault(item.key, _Entry(display=item.display))
                # Only the most recent meal of the window sets the onset
                if flare not in entry.flares:
                    entry.hits.append((flare, meal, onset))
                    entry.days.add(local_date(flare.start, tz))
                entry.flares.add(flare)

    def week_hits(entry: _Entry) -> list[tuple[Flare, MealRow, float]]:
        return [hit for hit in entry.hits if id(hit[0]) in week_flare_ids]

    # One meal before one symptom is a coincidence, not a pattern: a food is
    # only a suspect once it has come before symptoms on separate days
    # A food eaten regularly without trouble, that only came before a
    # symptom alongside a likelier cause, is not a suspect for that symptom.
    # Only history up to the end of this week counts, as above.
    fine = usually_fine_items(
        [m for m in meals if local_date(m.timestamp, tz) <= week_end],
        [s for s in symptoms if local_date(s.timestamp, tz) <= week_end],
        window_hours,
    )

    def usually_fine(key: str, entry: _Entry) -> bool:
        names = {
            name
            for flare, _, _ in week_hits(entry)
            for name in flare.names
            if not symptom_filter or name == symptom_filter
        }
        return all((f"ingredient:{key}", name) in fine for name in names)

    entries = {
        key: entry
        for key, entry in entries.items()
        if week_hits(entry)
        and len(entry.days) >= max(min_days, MIN_PATTERN_DAYS)
        and not usually_fine(key, entry)
    }

    week_meals = [m for m in meals if local_date(m.timestamp, tz) in dates]

    def count_with(pool: list[MealRow], key: str) -> int:
        return sum(
            1
            for meal in pool
            if any(i.dimension == "ingredient" and i.key == key for i in meal_items(meal))
        )

    def confidence_for(key: str) -> int:
        matching = [
            row.confidence
            for row in correlations
            if row.dimension == "ingredient"
            and normalize_item(row.food_name) == key
            and (not symptom_filter or row.symptom_name == symptom_filter)
        ]
        return max(matching, default=0)

    def suspect(key: str, entry: _Entry) -> Suspect:
        hits = week_hits(entry)
        # The latest symptom of each day, so the card shows the separate days
        by_day: dict[str, tuple[Flare, MealRow, float]] = {}
        for hit in sorted(entry.hits, key=lambda hit: hit[0].start, reverse=True):
            by_day.setdefault(local_date(hit[0].start, tz), hit)
        return Suspect(
            name=entry.display,
            flares_with_ingredient=len(hits),
            flares_total=len(flares),
            share=round2(len(hits) / len(flares)) if flares else 0,
            avg_onset_hours=round1(sum(h for _, _, h in hits) / len(hits)) if hits else None,
            times_logged_this_week=count_with(week_meals, key),
            exposures_all_time=count_with(meals, key),
            confidence=confidence_for(key),
            on_watchlist=key in watched,
            days_with_symptoms=len(entry.days),
            recent_pairs=[
                SuspectPair(
                    meal_id=meal.id,
                    meal_name=meal.name,
                    meal_at=meal.timestamp,
                    flare_at=flare.start,
                    symptoms=flare.names,
                    onset_hours=round1(onset),
                )
                for flare, meal, onset in list(by_day.values())[:3]
            ],
        )

    suspects = [suspect(key, entry) for key, entry in entries.items()]
    suspects.sort(key=lambda s: (-s.share, -s.confidence, s.name.casefold(), s.name))
    suspects = suspects[:TOP_SUSPECTS]

    # Each flare is attributed to its most recent prior meal
    buckets: dict[str, tuple[TimingWindow, dict[str, int]]] = {
        "0to4h": (TimingWindow(), {}),
        "4to12h": (TimingWindow(), {}),
        "12to24h": (TimingWindow(), {}),
    }
    for flare in flares:
        prior = meals_before(meals, flare.start, window_hours)
        if not prior:
            continue
        onset = hours_between(prior[0].timestamp, flare.start)
        name = "0to4h" if onset <= 4 else "4to12h" if onset <= 12 else "12to24h"
        window, counts = buckets[name]
        window.flares += 1
        for item in meal_items(prior[0]):
            if item.dimension == "ingredient":
                counts[item.display] = counts.get(item.display, 0) + 1
    for window, counts in buckets.values():
        window.top_ingredients = [
            name for name, _ in sorted(counts.items(), key=lambda kv: -kv[1])[:3]
        ]

    return SuspectsDigest(
        week_start=week_start,
        week_end=week_end,
        window_hours=window_hours,
        flares=len(flares),
        meals_evaluated=len(evaluated),
        lead_suspect=suspects[0].name if suspects else None,
        symptom_filters=symptom_filters,
        ingredients=suspects,
        timing_windows={name: window for name, (window, _) in buckets.items()},
    )


def pattern_days(
    meals: list[MealRow], flares: list[Flare], window_hours: int, tz: str
) -> dict[str, set[str]]:
    """The separate local days each ingredient was eaten before one of these flares."""
    days: dict[str, set[str]] = {}
    for flare in flares:
        day = local_date(flare.start, tz)
        for meal in meals_before(meals, flare.start, window_hours):
            for item in meal_items(meal):
                if item.dimension == "ingredient":
                    days.setdefault(item.key, set()).add(day)
    return days
