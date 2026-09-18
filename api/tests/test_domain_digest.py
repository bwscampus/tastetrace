"""Ported from app/test/digest.test.ts — the mockup week, and its numbers."""

from datetime import UTC, datetime

from app.domain.digest import compute_weekly_digest
from app.domain.rows import CorrelationRow, IngredientRow, MealRow, SettingsRow, SymptomRow
from app.domain.suspects import compute_suspects

TZ = "America/Los_Angeles"
SETTINGS = SettingsRow(correlation_window_hours=24, min_trigger_count=2, min_confidence=50)

_next_id = iter(range(1, 10_000))


def at(iso: str) -> datetime:
    return datetime.fromisoformat(iso).replace(tzinfo=UTC)


def meal(iso: str, name: str, ingredients: list[str], meal_type: str = "Lunch") -> MealRow:
    return MealRow(
        id=next(_next_id),
        name=name,
        meal_type=meal_type,
        timestamp=at(iso),
        ingredients=ingredients,
        ingredient_details=[IngredientRow(n) for n in ingredients],
    )


def symptom(iso: str, name: str, intensity: int, duration: int | None = None) -> SymptomRow:
    return SymptomRow(
        id=next(_next_id),
        name=name,
        severity="Moderate",
        intensity=intensity,
        duration_minutes=duration,
        catalog_key="acid_reflux" if name == "Acid Reflux" else "bloating",
        timestamp=at(iso),
    )


TOAST = ["sourdough bread", "avocado", "salt"]
MEALS = [
    meal("2026-09-11T19:45:00", "Avocado Sourdough Toast", TOAST),
    meal("2026-09-17T19:45:00", "Avocado Sourdough Toast", TOAST),
    meal("2026-09-14T15:00:00", "Oatmeal", ["oats"], "Breakfast"),
]
SYMPTOMS = [
    symptom("2026-09-11T21:29:00", "Acid Reflux", 3, 60),
    symptom("2026-09-11T21:30:00", "Bloating", 1, 20),
    symptom("2026-09-17T21:29:00", "Acid Reflux", 3, 60),
    symptom("2026-09-17T21:30:00", "Bloating", 1, 20),
]
CORRELATIONS = [
    CorrelationRow(
        food_name="sourdough bread",
        symptom_name="Acid Reflux",
        dimension="ingredient",
        confidence=62,
    )
]


def digest():
    return compute_weekly_digest(MEALS, SYMPTOMS, CORRELATIONS, "2026-09-11", TZ, SETTINGS, "2026-09-17")


def test_trends_hero_and_daily_bars():
    d = digest()
    assert d.week_end == "2026-09-17"
    assert [day.index for day in d.trends.days] == [6, 0, 0, 0, 0, 0, 6]

    friday = d.trends.days[0]
    assert (friday.weekday, friday.level, friday.occurrences, friday.max_intensity) == ("Fri", "high", 2, 3)

    assert d.trends.index == 1.7
    assert d.trends.baseline_index == 1.7  # all history is this week
    assert d.trends.delta_vs_baseline_percent == 0
    assert d.trends.occurrences == 4
    assert d.trends.flares == 2
    assert d.trends.discomfort_free_days == 5
    assert d.trends.severe_days == 2
    assert d.trends.severe_peak_day == "2026-09-11"
    assert d.trends.meal_log_depth == 0.14  # 3 of 21 slots
    assert d.has_next_week is False


def test_symptom_cards_carry_severity_duration_and_triggers():
    d = digest()
    assert d.symptoms.total == 4
    assert d.symptoms.distinct == 2

    reflux = next(card for card in d.symptoms.cards if card.name == "Acid Reflux")
    assert reflux.emoji == "🔥"
    assert reflux.occurrences == 2
    assert reflux.share_of_week == 0.5
    assert reflux.avg_severity10 == 6
    assert reflux.avg_duration_minutes == 60
    assert reflux.peak_day == "2026-09-11"
    assert reflux.top_triggers == ["sourdough bread"]

    windows = d.symptoms.onset_windows
    assert (windows.under1h, windows.from1to3h, windows.over3h, windows.unmatched) == (0, 4, 0, 0)


def test_suspects_rank_ingredients_eaten_before_flares():
    suspects = compute_suspects(MEALS, SYMPTOMS, CORRELATIONS, ["Sourdough Bread"], "2026-09-11", TZ, 24, None)

    assert suspects.flares == 2
    assert suspects.meals_evaluated == 2
    assert suspects.lead_suspect == "sourdough bread"
    assert suspects.window_hours == 24
    assert suspects.symptom_filters == [
        {"name": "All Symptoms", "count": 2},
        {"name": "Acid Reflux", "count": 2},
        {"name": "Bloating", "count": 2},
    ]

    lead = suspects.ingredients[0]
    assert lead.name == "sourdough bread"
    assert (lead.flares_with_ingredient, lead.flares_total, lead.share) == (2, 2, 1)
    assert lead.avg_onset_hours == 1.7
    assert lead.times_logged_this_week == 2
    assert lead.exposures_all_time == 2
    assert lead.confidence == 62
    assert lead.on_watchlist is True

    pair = lead.recent_pairs[0]
    assert pair.meal_name == "Avocado Sourdough Toast"
    assert pair.symptoms == ["Acid Reflux", "Bloating"]
    assert pair.onset_hours == 1.7

    assert suspects.timing_windows["0to4h"].flares == 2
    assert suspects.timing_windows["0to4h"].top_ingredients == ["sourdough bread", "avocado", "salt"]
    assert suspects.timing_windows["12to24h"].flares == 0
    assert not any(s.name == "oats" for s in suspects.ingredients)


def test_suspects_can_be_filtered_by_symptom():
    only_bloating = compute_suspects(MEALS, SYMPTOMS, CORRELATIONS, [], "2026-09-11", TZ, 24, "Bloating")
    assert only_bloating.flares == 2
    # The stored correlation is for reflux, so it contributes no confidence here
    assert only_bloating.ingredients[0].confidence == 0

    empty_week = compute_suspects(MEALS, SYMPTOMS, CORRELATIONS, [], "2026-09-18", TZ, 24, None)
    assert empty_week.flares == 0
