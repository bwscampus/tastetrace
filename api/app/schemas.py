"""API-facing shapes.

Every response the iOS app decodes is camelCase, so project schemas inherit
`CamelModel`: fields are declared snake_case (Python) and serialised camelCase
(JSON). `populate_by_name` means requests may send either spelling.
"""

from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator
from pydantic.alias_generators import to_camel

MealTypeName = Literal["Breakfast", "Lunch", "Dinner", "Snack"]
Trimmed = Annotated[str, StringConstraints(strip_whitespace=True)]


class CamelModel(BaseModel):
    model_config = ConfigDict(
        alias_generator=to_camel,
        populate_by_name=True,
        from_attributes=True,
    )


class IngredientDetail(CamelModel):
    """One ingredient of a meal, with how it was prepared."""

    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]
    cook_method: Annotated[str, StringConstraints(strip_whitespace=True, max_length=40)] | None = None


# ── Profile and settings ────────────────────────────────────────────────────


class ProfileRead(CamelModel):
    id: str
    email: str
    first_name: str | None = None
    last_name: str | None = None
    display_name: str | None = None
    avatar_emoji: str | None = None
    discovery_purpose: str | None = None
    sensitivity_tags: list[str] = Field(default_factory=list)
    created_at: datetime | None = None
    journaler_days: int
    first_log_at: datetime | None = None


class ProfilePatch(CamelModel):
    first_name: Annotated[str, StringConstraints(strip_whitespace=True, max_length=60)] | None = None
    last_name: Annotated[str, StringConstraints(strip_whitespace=True, max_length=60)] | None = None
    display_name: Annotated[str, StringConstraints(strip_whitespace=True, max_length=80)] | None = None
    avatar_emoji: Annotated[str, StringConstraints(strip_whitespace=True, max_length=8)] | None = None
    discovery_purpose: Annotated[str, StringConstraints(strip_whitespace=True, max_length=200)] | None = None
    sensitivity_tags: list[Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=40)]] | None = Field(default=None, max_length=20)


class SettingsRead(CamelModel):
    timezone: str
    correlation_window_hours: int
    min_trigger_count: int
    min_confidence: int
    streak_meals_per_day: int
    nudge_time: str
    nudges_enabled: bool
    meal_check_ins_enabled: bool
    updated_at: datetime | None = None


class SettingsPatch(CamelModel):
    timezone: Annotated[str, StringConstraints(min_length=1, max_length=64)] | None = None
    correlation_window_hours: Annotated[int, Field(ge=1, le=72)] | None = None
    min_trigger_count: Annotated[int, Field(ge=1, le=20)] | None = None
    min_confidence: Annotated[int, Field(ge=0, le=100)] | None = None
    streak_meals_per_day: Annotated[int, Field(ge=1, le=6)] | None = None
    nudge_time: Annotated[str, StringConstraints(pattern=r"^([01]\d|2[0-3]):[0-5]\d$")] | None = None
    nudges_enabled: bool | None = None
    meal_check_ins_enabled: bool | None = None


# ── Meals ───────────────────────────────────────────────────────────────────


class MealRead(CamelModel):
    id: int
    user_id: str | None = None
    name: str
    meal_type: str
    timestamp: datetime
    notes: str | None = None
    is_custom: bool | None = None
    ingredients: list[str] = Field(default_factory=list)
    ingredient_details: list[IngredientDetail] | None = None
    dish_id: int | None = None
    contains_gluten: bool | None = None
    contains_dairy: bool | None = None
    contains_grains: bool | None = None
    contains_sugar: bool | None = None
    contains_nuts: bool | None = None
    date: str
    # Only set by /api/entries/date and the ledger export
    suspicious_for: list[str] | None = None
    suspicion: Literal["window", "correlated"] | None = None


class MealCreate(CamelModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]
    meal_type: MealTypeName
    timestamp: datetime | None = None
    tz: str | None = None
    notes: str | None = None
    is_custom: bool | None = True
    ingredients: list[str] | None = None
    ingredient_details: list[IngredientDetail] | None = None
    dish_id: int | None = None
    contains_gluten: bool = False
    contains_dairy: bool = False
    contains_grains: bool = False
    contains_sugar: bool = False
    contains_nuts: bool = False


class MealPatch(CamelModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)] | None = None
    meal_type: MealTypeName | None = None
    timestamp: datetime | None = None
    tz: str | None = None
    notes: str | None = None
    ingredients: list[str] | None = None
    ingredient_details: list[IngredientDetail] | None = None
    contains_gluten: bool | None = None
    contains_dairy: bool | None = None
    contains_grains: bool | None = None
    contains_sugar: bool | None = None
    contains_nuts: bool | None = None


# ── Symptoms ────────────────────────────────────────────────────────────────


class SymptomRead(CamelModel):
    id: int
    user_id: str | None = None
    name: str
    severity: str
    intensity: int | None = None
    duration_minutes: int | None = None
    catalog_key: str | None = None
    timestamp: datetime
    notes: str | None = None
    date: str
    emoji: str | None = None
    body_region: str | None = None


class SymptomCreate(CamelModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)]
    catalog_key: Annotated[str, StringConstraints(max_length=80)] | None = None
    severity: str | None = None
    intensity: Annotated[int, Field(ge=1, le=5)] | None = None
    duration_minutes: Annotated[int, Field(ge=0, le=60 * 24 * 7)] | None = None
    timestamp: datetime | None = None
    tz: str | None = None
    notes: str | None = None

    @model_validator(mode="after")
    def _needs_a_level(self) -> "SymptomCreate":
        if self.severity is None and self.intensity is None:
            raise ValueError("Either severity or intensity is required")
        return self


class SymptomPatch(CamelModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)] | None = None
    severity: str | None = None
    intensity: Annotated[int, Field(ge=1, le=5)] | None = None
    duration_minutes: Annotated[int, Field(ge=0, le=60 * 24 * 7)] | None = None
    catalog_key: Annotated[str, StringConstraints(max_length=80)] | None = None
    timestamp: datetime | None = None
    tz: str | None = None
    notes: str | None = None


class SymptomBatchItem(CamelModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)]
    catalog_key: Annotated[str, StringConstraints(max_length=80)] | None = None
    intensity: Annotated[int, Field(ge=1, le=5)]


class SymptomBatch(CamelModel):
    timestamp: datetime | None = None
    tz: str | None = None
    duration_minutes: Annotated[int, Field(ge=0, le=60 * 24 * 7)] | None = None
    notes: Annotated[str, StringConstraints(max_length=2000)] | None = None
    items: Annotated[list[SymptomBatchItem], Field(min_length=1, max_length=20)]


class CatalogItem(CamelModel):
    key: str
    name: str
    emoji: str
    body_region: str | None = None


class CustomSymptomRead(CamelModel):
    id: int
    key: str
    name: str
    emoji: str
    body_region: str | None = None


class CustomSymptomCreate(CamelModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=60)]
    emoji: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=8)] | None = None
    body_region: Annotated[str, StringConstraints(strip_whitespace=True, max_length=60)] | None = None


class SymptomCatalogRead(CamelModel):
    defaults: list[CatalogItem]
    custom: list[CustomSymptomRead]


# ── Dishes ──────────────────────────────────────────────────────────────────


class DishRead(CamelModel):
    id: int
    user_id: str | None = None
    name: str
    emoji: str
    ingredients: list[IngredientDetail] = Field(default_factory=list)
    contains_gluten: bool | None = None
    contains_dairy: bool | None = None
    contains_grains: bool | None = None
    contains_sugar: bool | None = None
    contains_nuts: bool | None = None
    times_logged: int
    last_logged_at: datetime | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


class DishCreate(CamelModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]
    emoji: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=16)] = "🍽️"
    ingredients: list[IngredientDetail] = Field(default_factory=list)
    contains_gluten: bool = False
    contains_dairy: bool = False
    contains_grains: bool = False
    contains_sugar: bool = False
    contains_nuts: bool = False


class DishPatch(CamelModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)] | None = None
    emoji: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=16)] | None = None
    ingredients: list[IngredientDetail] | None = None
    contains_gluten: bool | None = None
    contains_dairy: bool | None = None
    contains_grains: bool | None = None
    contains_sugar: bool | None = None
    contains_nuts: bool | None = None


class DishLogOverrides(CamelModel):
    ingredient_details: list[IngredientDetail] | None = None


class DishLog(CamelModel):
    meal_type: MealTypeName
    timestamp: datetime | None = None
    tz: str | None = None
    notes: Annotated[str, StringConstraints(max_length=2000)] | None = None
    overrides: DishLogOverrides | None = None


# ── Watchlist ───────────────────────────────────────────────────────────────


class WatchlistRead(CamelModel):
    id: int
    ingredient: str
    source: str
    created_at: datetime | None = None
    confidence_max: int = 0


class WatchlistCreate(CamelModel):
    ingredient: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]
    source: Literal["manual", "suspect", "synthesis"] = "manual"


# ── Entries ─────────────────────────────────────────────────────────────────


class DayEntries(CamelModel):
    date: str
    meals: list[MealRead]
    symptoms: list[SymptomRead]
    flares: int
    entries: int


class DayMarker(CamelModel):
    meals: int
    symptoms: int
    max_intensity: int
    status: Literal["ok", "meal", "symptom"]


# ── AI synthesis ────────────────────────────────────────────────────────────


class SynthesisRequest(CamelModel):
    week_start: str | None = None
    symptom: Annotated[str, StringConstraints(max_length=80)] | None = None
    tz: str | None = None


class SynthesisRead(CamelModel):
    text: str
    source: Literal["claude", "rules"]
    model: str | None = None
    cached: bool
    generated_at: datetime
    suggested_watchlist: list[str] = Field(default_factory=list)
