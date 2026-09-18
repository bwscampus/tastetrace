"""Plain row shapes the analytics work on.

The pure modules take these rather than ORM objects, so the tests can build
fixtures without a database and the same functions serve both the request
path and the exports.
"""

from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class IngredientRow:
    name: str
    cook_method: str | None = None


@dataclass
class MealRow:
    id: int
    name: str
    meal_type: str
    timestamp: datetime
    ingredients: list[str] = field(default_factory=list)
    ingredient_details: list[IngredientRow] | None = None
    notes: str | None = None
    dish_id: int | None = None


@dataclass
class SymptomRow:
    id: int
    name: str
    severity: str
    timestamp: datetime
    intensity: int | None = None
    duration_minutes: int | None = None
    catalog_key: str | None = None
    notes: str | None = None


@dataclass
class CorrelationRow:
    food_name: str
    symptom_name: str
    dimension: str
    exposures: int = 0
    flare_exposures: int = 0
    occurrences: int = 0
    confidence: int = 0
    is_ingredient: bool = False
    hit_rate: float = 0.0
    baseline_rate: float | None = None
    lift: float | None = None
    avg_onset_hours: float | None = None
    window_hours: int | None = None
    last_flare_at: datetime | None = None


@dataclass
class SettingsRow:
    timezone: str = "UTC"
    correlation_window_hours: int = 24
    min_trigger_count: int = 2
    min_confidence: int = 50
    streak_meals_per_day: int = 2
    nudge_time: str = "20:30"
    nudges_enabled: bool = True
    meal_check_ins_enabled: bool = False
