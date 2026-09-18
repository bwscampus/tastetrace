"""Ported from app/test/correlations.test.ts — same fixtures, same numbers."""

from datetime import UTC, datetime

from app.domain.correlations import compute_correlations, confidence_score, suspicion_for, tier_for
from app.domain.flares import cluster_flares, onset_hours
from app.domain.rows import CorrelationRow, IngredientRow, MealRow, SettingsRow, SymptomRow

SETTINGS = SettingsRow(correlation_window_hours=24, min_trigger_count=2)


def at(iso: str) -> datetime:
    return datetime.fromisoformat(iso).replace(tzinfo=UTC)


_next_id = iter(range(1, 10_000))


def meal(iso: str, name: str, ingredients: list[tuple[str, str | None]] | None = None) -> MealRow:
    details = [IngredientRow(n, c) for n, c in ingredients] if ingredients else None
    return MealRow(
        id=next(_next_id),
        name=name,
        meal_type="Lunch",
        timestamp=at(iso),
        ingredients=[n for n, _ in ingredients] if ingredients else [],
        ingredient_details=details,
    )


def symptom(iso: str, name: str, intensity: int = 3) -> SymptomRow:
    return SymptomRow(id=next(_next_id), name=name, severity="Moderate", intensity=intensity, timestamp=at(iso))


def test_flares_cluster_within_thirty_minutes_and_find_their_onset_meal():
    flares = cluster_flares(
        [
            symptom("2026-09-11T21:29:00", "Acid Reflux", 3),
            symptom("2026-09-11T21:40:00", "Bloating", 1),
            symptom("2026-09-12T10:00:00", "Headache", 4),
        ]
    )
    assert len(flares) == 2
    assert flares[0].names == ["Acid Reflux", "Bloating"]
    assert flares[0].max_intensity == 3

    meals = [meal("2026-09-11T19:45:00", "Toast"), meal("2026-09-10T19:45:00", "Old")]
    assert round(onset_hours(meals, flares[0].start, 24), 2) == 1.73
    assert onset_hours(meals, flares[1].start, 4) is None


def test_scoring_counts_exposures_without_a_flare():
    # Sourdough eaten 4 times, reflux followed 3 of them; oats eaten 4 times, never followed.
    meals = [
        meal("2026-09-01T12:00:00", "Toast", [("sourdough bread", "toasted")]),
        meal("2026-09-02T12:00:00", "Toast", [("sourdough bread", "toasted")]),
        meal("2026-09-03T12:00:00", "Toast", [("sourdough bread", "toasted")]),
        meal("2026-09-04T12:00:00", "Toast", [("sourdough bread", "toasted")]),
        meal("2026-09-05T12:00:00", "Oats", [("oats", None)]),
        meal("2026-09-06T12:00:00", "Oats", [("oats", None)]),
        meal("2026-09-07T12:00:00", "Oats", [("oats", None)]),
        meal("2026-09-08T12:00:00", "Oats", [("oats", None)]),
    ]
    symptoms = [
        symptom("2026-09-01T14:00:00", "Acid Reflux"),
        symptom("2026-09-02T14:00:00", "Acid Reflux"),
        symptom("2026-09-03T14:00:00", "Acid Reflux"),
    ]

    rows = compute_correlations(meals, symptoms, SETTINGS)
    sourdough = next(r for r in rows if r.dimension == "ingredient" and r.food_name == "sourdough bread")

    assert (sourdough.exposures, sourdough.flare_exposures) == (4, 3)
    assert sourdough.hit_rate == 0.75
    assert sourdough.baseline_rate == 3 / 8
    assert sourdough.lift == 2
    assert sourdough.avg_onset_hours == 2
    assert sourdough.occurrences == 3
    assert sourdough.is_ingredient is True
    assert sourdough.window_hours == 24
    assert sourdough.confidence == confidence_score(0.75, 3, 2, "ingredient") == 58
    assert tier_for(sourdough.confidence) == "likely"

    # Cooking styles are the same evidence, one step weaker
    toasted = next(r for r in rows if r.dimension == "cook_method")
    assert toasted.confidence == sourdough.confidence - 10 == 48

    # A food never followed by the symptom produces no row at all
    assert not any(r.food_name == "oats" for r in rows)
    # The whole-food row still exists for the meal name
    assert any(r.dimension == "food" and r.food_name == "Toast" and not r.is_ingredient for r in rows)


def test_thin_evidence_never_passes_the_default_floor():
    rows = compute_correlations(
        [meal("2026-09-01T12:00:00", "Toast", [("sourdough bread", None)])],
        [symptom("2026-09-01T14:00:00", "Acid Reflux")],
        SETTINGS,
    )
    assert rows[0].confidence <= 49
    assert compute_correlations([], [], SETTINGS) == []


def test_a_meal_is_suspicious_when_a_symptom_follows_it():
    m = meal("2026-09-11T19:45:00", "Avocado Sourdough Toast", [("sourdough bread", None)])
    symptoms = [symptom("2026-09-11T21:29:00", "Acid Reflux")]

    assert suspicion_for(m, symptoms, [], 24, 50) == (["Acid Reflux"], "window")

    # Once an ingredient of the meal is a known trigger, the flag is upgraded.
    known = [
        CorrelationRow(
            food_name="Sourdough Bread",  # matched case- and space-insensitively
            symptom_name="Acid Reflux",
            dimension="ingredient",
            confidence=72,
        )
    ]
    assert suspicion_for(m, symptoms, known, 24, 50)[1] == "correlated"
    # Outside the window nothing is flagged
    assert suspicion_for(m, symptoms, known, 1, 50) == ([], None)
