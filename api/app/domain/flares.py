"""Grouping symptoms into flares, and finding the meals that preceded them."""

from dataclasses import dataclass, field
from datetime import datetime, timedelta

from app.domain.rows import MealRow, SymptomRow
from app.domain.severity import intensity_from_severity
from app.domain.time import as_utc

# Symptoms logged within this long of the flare's start are the same flare
FLARE_CLUSTER_MINUTES = 30


def intensity_of(symptom: SymptomRow) -> int:
    if symptom.intensity is not None:
        return symptom.intensity
    return intensity_from_severity(symptom.severity)


@dataclass(eq=False)  # identity hashing: flares are collected in sets
class Flare:
    start: datetime
    end: datetime
    symptoms: list[SymptomRow] = field(default_factory=list)
    names: list[str] = field(default_factory=list)
    max_intensity: int = 0


def cluster_flares(symptoms: list[SymptomRow]) -> list[Flare]:
    """One flare per burst of symptoms.

    The window is measured from the flare's start, not the previous symptom,
    so a long trickle of entries can't chain into one endless flare.
    """
    window = timedelta(minutes=FLARE_CLUSTER_MINUTES)
    flares: list[Flare] = []
    for symptom in sorted(symptoms, key=lambda s: as_utc(s.timestamp)):
        at = as_utc(symptom.timestamp)
        current = flares[-1] if flares else None
        if current is not None and at - current.start <= window:
            current.symptoms.append(symptom)
            current.end = at
            if symptom.name not in current.names:
                current.names.append(symptom.name)
            current.max_intensity = max(current.max_intensity, intensity_of(symptom))
        else:
            flares.append(
                Flare(
                    start=at,
                    end=at,
                    symptoms=[symptom],
                    names=[symptom.name],
                    max_intensity=intensity_of(symptom),
                )
            )
    return flares


def hours_between(earlier: datetime, later: datetime) -> float:
    return (as_utc(later) - as_utc(earlier)).total_seconds() / 3600


def meals_before(meals: list[MealRow], at: datetime, window_hours: float) -> list[MealRow]:
    """Meals eaten in the window before `at`, most recent first.

    Strictly before: a meal logged at the same instant as the symptom cannot
    have caused it.
    """
    within = [m for m in meals if 0 < hours_between(m.timestamp, at) <= window_hours]
    return sorted(within, key=lambda m: as_utc(m.timestamp), reverse=True)


def onset_hours(meals: list[MealRow], at: datetime, window_hours: float) -> float | None:
    """Hours from the most recent meal in the window, or None if there was none."""
    latest = meals_before(meals, at, window_hours)
    return hours_between(latest[0].timestamp, at) if latest else None
