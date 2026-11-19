"""History search: every time a food was eaten, or a symptom was logged,
and what came either side of it within the correlation window."""

from dataclasses import dataclass, field
from datetime import datetime

from app.domain.flares import hours_between
from app.domain.foods import meal_items, normalize_item
from app.domain.rounding import round1
from app.domain.rows import MealRow, SymptomRow
from app.domain.time import as_utc, local_date

# Enough to scroll a long history without shipping the whole log
MAX_OCCURRENCES = 200


@dataclass
class SymptomAfter:
    name: str
    at: datetime
    onset_hours: float


@dataclass
class Occurrence:
    meal_id: int
    meal_name: str
    meal_type: str
    meal_at: datetime
    date: str
    # The meal's foods or ingredients that matched, as the user wrote them
    matched: list[str]
    symptoms_after: list[SymptomAfter] = field(default_factory=list)


@dataclass
class FoodOccurrences:
    query: str
    window_hours: int
    total: int
    with_symptoms: int
    occurrences: list[Occurrence]


def matching_items(meal: MealRow, key: str) -> list[str]:
    """The meal's foods and ingredients that contain the search text."""
    matched: list[str] = []
    for item in meal_items(meal):
        if item.dimension == "cook_method" or key not in item.key:
            continue
        if item.display.casefold() not in (m.casefold() for m in matched):
            matched.append(item.display)
    if not matched and key in normalize_item(meal.name):
        matched.append(meal.name.strip())
    return matched


def find_occurrences(
    meals: list[MealRow],
    symptoms: list[SymptomRow],
    query: str,
    tz: str,
    window_hours: int,
) -> FoodOccurrences:
    key = normalize_item(query)
    found: list[Occurrence] = []
    for meal in sorted(meals, key=lambda m: as_utc(m.timestamp), reverse=True):
        matched = matching_items(meal, key)
        if not matched:
            continue
        after = sorted(
            (
                SymptomAfter(name=s.name, at=s.timestamp, onset_hours=round1(onset))
                for s in symptoms
                if 0
                < (onset := hours_between(meal.timestamp, s.timestamp))
                <= window_hours
            ),
            key=lambda s: as_utc(s.at),
        )
        found.append(
            Occurrence(
                meal_id=meal.id,
                meal_name=meal.name,
                meal_type=meal.meal_type,
                meal_at=meal.timestamp,
                date=local_date(meal.timestamp, tz),
                matched=matched,
                symptoms_after=after,
            )
        )

    return FoodOccurrences(
        query=query.strip(),
        window_hours=window_hours,
        total=len(found),
        with_symptoms=sum(1 for o in found if o.symptoms_after),
        occurrences=found[:MAX_OCCURRENCES],
    )


@dataclass
class MealBefore:
    meal_id: int
    meal_name: str
    at: datetime
    onset_hours: float


@dataclass
class SymptomOccurrence:
    symptom_id: int
    name: str
    severity: str
    intensity: int | None
    at: datetime
    date: str
    # Meals eaten in the window before it, most recent first
    meals_before: list[MealBefore] = field(default_factory=list)


@dataclass
class SymptomOccurrences:
    query: str
    window_hours: int
    total: int
    with_meals: int
    occurrences: list[SymptomOccurrence]


def find_symptom_occurrences(
    meals: list[MealRow],
    symptoms: list[SymptomRow],
    query: str,
    tz: str,
    window_hours: int,
) -> SymptomOccurrences:
    key = normalize_item(query)
    found: list[SymptomOccurrence] = []
    for symptom in sorted(symptoms, key=lambda s: as_utc(s.timestamp), reverse=True):
        if key not in normalize_item(symptom.name):
            continue
        before = sorted(
            (
                MealBefore(
                    meal_id=m.id,
                    meal_name=m.name,
                    at=m.timestamp,
                    onset_hours=round1(onset),
                )
                for m in meals
                if 0
                < (onset := hours_between(m.timestamp, symptom.timestamp))
                <= window_hours
            ),
            key=lambda m: as_utc(m.at),
            reverse=True,
        )
        found.append(
            SymptomOccurrence(
                symptom_id=symptom.id,
                name=symptom.name,
                severity=symptom.severity,
                intensity=symptom.intensity,
                at=symptom.timestamp,
                date=local_date(symptom.timestamp, tz),
                meals_before=before,
            )
        )

    return SymptomOccurrences(
        query=query.strip(),
        window_hours=window_hours,
        total=len(found),
        with_meals=sum(1 for o in found if o.meals_before),
        occurrences=found[:MAX_OCCURRENCES],
    )
