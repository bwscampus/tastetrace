"""Which foods precede which symptoms, and how much to believe it.

The engine counts how often an item was eaten *without* the symptom as well
as with it, so a food eaten constantly scores lower than one that only shows
up before a flare.
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


def compute_correlations(
    meals: list[MealRow], symptoms: list[SymptomRow], settings: SettingsRow
) -> list[CorrelationRow]:
    """Every (item, symptom) association for one user."""
    window = settings.correlation_window_hours
    if not meals or not symptoms:
        return []

    symptom_names = list(dict.fromkeys(s.name for s in symptoms))
    by_name: dict[str, list[SymptomRow]] = {name: [] for name in symptom_names}
    for symptom in symptoms:
        by_name[symptom.name].append(symptom)

    # The first occurrence of each symptom inside the window after each meal
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

    # How often each symptom follows *any* meal — the denominator
    baseline = {
        name: sum(1 for hits in followed if name in hits) / len(meals)
        for name in symptom_names
    }

    grouped: dict[str, tuple[str, Dimension, list[int]]] = {}
    for index, meal in enumerate(meals):
        for item in meal_items(meal):
            display, dimension, indexes = grouped.get(item.id, (item.display, item.dimension, []))
            indexes.append(index)
            grouped[item.id] = (display, dimension, indexes)

    rows: list[CorrelationRow] = []
    for display, dimension, indexes in grouped.values():
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
        and row.confidence >= min_confidence
        and f"{row.dimension}:{normalize_item(row.food_name)}" in item_ids
        for row in rows
    )
    return names, "correlated" if correlated else "window"
