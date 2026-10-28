"""Which foods precede which symptoms, and how much to believe it.

The engine counts how often an item was eaten *without* the symptom as well
as with it, so a food eaten constantly scores lower than one that only shows
up before a flare.

It also looks for foods that are usually fine: eaten regularly without the
symptom, and only followed by it when something more suspicious was eaten
too. Rice eaten every day, and with cheese on the two days reflux followed,
is the cheese's evidence, not the rice's.
"""

import math
from dataclasses import dataclass
from datetime import datetime
from typing import Literal

from app.domain.flares import hours_between
from app.domain.foods import Dimension, meal_items, normalize_item
from app.domain.rounding import js_round
from app.domain.rows import CorrelationRow, MealRow, SettingsRow, SymptomRow

Tier = Literal["strong", "likely", "watch"]

# A row this weak is only shown when the user lowers their confidence floor
THIN_EVIDENCE_CAP = 49
# With no baseline to compare against, treat the lift as strongly positive
MAX_LIFT = 5.0
# Confidence ceiling for a food the person usually eats without trouble
USUALLY_FINE_CAP = 20
# Times a food must be eaten without the symptom to count as a regular, safe food
MIN_FINE_EXPOSURES = 3
# The kinds of item the Triggers page shows. History only calls a meal a
# trigger when it matches one of these, so the two screens agree.
TRIGGER_PAGE_DIMENSIONS = ("ingredient", "cook_method")


def tier_for(confidence: int) -> Tier:
    if confidence >= 75:
        return "strong"
    if confidence >= 50:
        return "likely"
    return "watch"


def confidence_score(
    hit_rate: float, flare_exposures: int, lift: float, dimension: Dimension
) -> int:
    """0-100 from three things: how often the item was followed by the symptom,
    how much evidence there is, and how that compares with the symptom's base
    rate after any meal.
    """
    support = 1 - math.exp(-flare_exposures / 2)
    lift_factor = min(max(lift / 2, 0), 1)
    confidence = js_round(100 * hit_rate * support * (0.5 + 0.5 * lift_factor))
    if dimension == "cook_method":
        confidence -= 10
    return min(max(confidence, 0), 100)


@dataclass
class _Follow:
    onset_hours: float
    at: datetime


@dataclass
class _History:
    symptom_names: list[str]
    # Per meal, the first occurrence of each symptom inside the window after it
    followed: list[dict[str, _Follow]]
    # Per item id: its display name, dimension and the indexes of the meals it was in
    grouped: dict[str, tuple[str, Dimension, list[int]]]


def _history(meals: list[MealRow], symptoms: list[SymptomRow], window: int) -> _History:
    symptom_names = list(dict.fromkeys(s.name for s in symptoms))
    by_name: dict[str, list[SymptomRow]] = {name: [] for name in symptom_names}
    for symptom in symptoms:
        by_name[symptom.name].append(symptom)

    followed: list[dict[str, _Follow]] = []
    for meal in meals:
        hits: dict[str, _Follow] = {}
        for name in symptom_names:
            best: _Follow | None = None
            for symptom in by_name[name]:
                gap = hours_between(meal.timestamp, symptom.timestamp)
                if 0 < gap <= window and (best is None or gap < best.onset_hours):
                    best = _Follow(onset_hours=gap, at=symptom.timestamp)
            if best is not None:
                hits[name] = best
        followed.append(hits)

    grouped: dict[str, tuple[str, Dimension, list[int]]] = {}
    for index, meal in enumerate(meals):
        for item in meal_items(meal):
            display, dimension, indexes = grouped.get(item.id, (item.display, item.dimension, []))
            indexes.append(index)
            grouped[item.id] = (display, dimension, indexes)

    return _History(symptom_names, followed, grouped)


def _usually_fine(history: _History) -> set[tuple[str, str]]:
    """(item id, symptom) pairs where the item is a regular, safe food.

    An item is usually fine for a symptom when it was eaten at least
    MIN_FINE_EXPOSURES times without the symptom, most of the times it was
    eaten were fine, and every time the symptom did follow, an item of the
    same kind with a higher hit rate had been eaten before that same symptom.
    Items that are always eaten together have the same rate, so neither
    explains the other away.
    """
    followed = history.followed
    fine: set[tuple[str, str]] = set()
    for name in history.symptom_names:
        # Per item: its hit rate, its exposures without the symptom, and the
        # symptom occurrences it came before
        stats: dict[str, tuple[Dimension, float, int, set[datetime]]] = {}
        for item_id, (_, dimension, indexes) in history.grouped.items():
            flared = [i for i in indexes if name in followed[i]]
            if flared:
                events = {followed[i][name].at for i in flared}
                stats[item_id] = (dimension, len(flared) / len(indexes), len(indexes) - len(flared), events)

        for item_id, (dimension, rate, clean, events) in stats.items():
            if clean < MIN_FINE_EXPOSURES or rate > 0.5:
                continue
            explained = set().union(
                *(
                    other_events
                    for other_id, (other_dimension, other_rate, _, other_events) in stats.items()
                    if other_id != item_id and other_dimension == dimension and other_rate > rate
                )
            )
            if events <= explained:
                fine.add((item_id, name))
    return fine


def usually_fine_items(
    meals: list[MealRow], symptoms: list[SymptomRow], window_hours: int
) -> set[tuple[str, str]]:
    """(item id, symptom) pairs for foods the person eats regularly without
    trouble, which only came before the symptom alongside a likelier cause."""
    if not meals or not symptoms:
        return set()
    return _usually_fine(_history(meals, symptoms, window_hours))


def compute_correlations(
    meals: list[MealRow], symptoms: list[SymptomRow], settings: SettingsRow
) -> list[CorrelationRow]:
    """Every (item, symptom) association for one user."""
    window = settings.correlation_window_hours
    if not meals or not symptoms:
        return []

    history = _history(meals, symptoms, window)
    symptom_names, followed = history.symptom_names, history.followed

    # How often each symptom follows *any* meal — the denominator
    baseline = {
        name: sum(1 for hits in followed if name in hits) / len(meals)
        for name in symptom_names
    }
    fine = _usually_fine(history)

    rows: list[CorrelationRow] = []
    for item_id, (display, dimension, indexes) in history.grouped.items():
        for name in symptom_names:
            exposures = len(indexes)
            hits = [followed[i][name] for i in indexes if name in followed[i]]
            flare_exposures = len(hits)
            if flare_exposures == 0:
                continue

            hit_rate = flare_exposures / exposures
            base = baseline.get(name, 0)
            lift = min(hit_rate / base, MAX_LIFT) if base > 0 else MAX_LIFT
            confidence = confidence_score(hit_rate, flare_exposures, lift, dimension)
            if exposures < 2 or flare_exposures < settings.min_trigger_count:
                confidence = min(confidence, THIN_EVIDENCE_CAP)
            if (item_id, name) in fine:
                confidence = min(confidence, USUALLY_FINE_CAP)

            rows.append(
                CorrelationRow(
                    food_name=display,
                    symptom_name=name,
                    dimension=dimension,
                    exposures=exposures,
                    flare_exposures=flare_exposures,
                    occurrences=flare_exposures,
                    confidence=confidence,
                    is_ingredient=dimension != "food",
                    hit_rate=hit_rate,
                    baseline_rate=base,
                    lift=lift,
                    avg_onset_hours=sum(h.onset_hours for h in hits) / flare_exposures,
                    window_hours=window,
                    last_flare_at=max(h.at for h in hits),
                )
            )

    rows.sort(key=lambda r: (-r.confidence, -r.flare_exposures, r.food_name.casefold(), r.food_name))
    return rows


def suspicion_for(
    meal: MealRow,
    symptoms: list[SymptomRow],
    rows: list[CorrelationRow],
    window_hours: int,
    min_confidence: int,
) -> tuple[list[str], str | None]:
    """Whether a meal is worth flagging in the timeline.

    "window" means a symptom simply followed it; "correlated" means one of its
    items is already a confident trigger for that symptom.
    """
    names = list(
        dict.fromkeys(
            s.name for s in symptoms if 0 < hours_between(meal.timestamp, s.timestamp) <= window_hours
        )
    )
    if not names:
        return [], None

    item_ids = {item.id for item in meal_items(meal)}
    correlated = any(
        row.symptom_name in names
        and row.dimension in TRIGGER_PAGE_DIMENSIONS
        and row.confidence >= min_confidence
        and f"{row.dimension}:{normalize_item(row.food_name)}" in item_ids
        for row in rows
    )
    return names, "correlated" if correlated else "window"
