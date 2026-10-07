"""API-facing shapes.

Every response the iOS app decodes is camelCase, so project schemas inherit
`CamelModel`: fields are declared snake_case (Python) and serialised camelCase
(JSON). `populate_by_name` means requests may send either spelling.
"""

from datetime import UTC, datetime
from typing import Annotated, Literal

from pydantic import (
    BaseModel,
    BeforeValidator,
    ConfigDict,
    EmailStr,
    Field,
    PlainSerializer,
    StringConstraints,
    model_validator,
)
from pydantic.alias_generators import to_camel

from app.config import settings


def _iso_millis_z(value: datetime) -> str:
    """ISO-8601 with exactly three fractional digits and a Z suffix.

    The iOS client decodes dates with ISO8601DateFormatter, whose
    .withFractionalSeconds option accepts three digits and nothing else.
    Pydantic's default emits six (or "+00:00"), which fails to decode, so
    every timestamp on the wire goes through this.
    """
    utc = value.astimezone(UTC) if value.tzinfo else value.replace(tzinfo=UTC)
    return f"{utc:%Y-%m-%dT%H:%M:%S}.{utc.microsecond // 1000:03d}Z"


# Use for every datetime the API returns.
UtcDatetime = Annotated[
    datetime, PlainSerializer(_iso_millis_z, return_type=str, when_used="json")
]

# The client reads ids as strings; SQLAlchemy hands back UUID objects.
UuidStr = Annotated[str, BeforeValidator(lambda v: str(v) if v is not None else v)]

MealTypeName = Literal["Breakfast", "Lunch", "Dinner", "Snack"]
DataSharing = Literal["private", "practitioner", "research"]
ClockTime = Annotated[str, StringConstraints(pattern=r"^([01]\d|2[0-3]):[0-5]\d$")]
Trimmed = Annotated[str, StringConstraints(strip_whitespace=True)]
# Request-size caps (API-2): every free-text field and list a client can send
# is bounded, so one request cannot store megabytes or stall correlation work.
Notes = Annotated[str, StringConstraints(max_length=2000)]
TzName = Annotated[str, StringConstraints(max_length=64)]
SeverityName = Annotated[str, StringConstraints(max_length=20)]
IngredientName = Annotated[str, StringConstraints(strip_whitespace=True, max_length=100)]
IngredientList = Annotated[list[IngredientName], Field(max_length=50)]


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
    id: UuidStr
    email: str
    first_name: str | None = None
    last_name: str | None = None
    display_name: str | None = None
    avatar_emoji: str | None = None
    discovery_purpose: str | None = None
    sensitivity_tags: list[str] = Field(default_factory=list)
    data_sharing: str | None = None
    onboarding_completed_at: UtcDatetime | None = None
    created_at: UtcDatetime | None = None
    journaler_days: int
    first_log_at: UtcDatetime | None = None


class ProfilePatch(CamelModel):
    first_name: Annotated[str, StringConstraints(strip_whitespace=True, max_length=60)] | None = None
    last_name: Annotated[str, StringConstraints(strip_whitespace=True, max_length=60)] | None = None
    display_name: Annotated[str, StringConstraints(strip_whitespace=True, max_length=80)] | None = None
    avatar_emoji: Annotated[str, StringConstraints(strip_whitespace=True, max_length=8)] | None = None
    discovery_purpose: Annotated[str, StringConstraints(strip_whitespace=True, max_length=500)] | None = None
    sensitivity_tags: list[Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=40)]] | None = Field(default=None, max_length=20)
    data_sharing: DataSharing | None = None
    # true stamps onboarding_completed_at (once); false clears it
    onboarding_completed: bool | None = None


class SettingsRead(CamelModel):
    timezone: str
    correlation_window_hours: int
    min_trigger_count: int
    min_confidence: int
    streak_meals_per_day: int
    nudge_time: str
    nudges_enabled: bool
    meal_check_ins_enabled: bool
    breakfast_time: str
    lunch_time: str
    dinner_time: str
    updated_at: UtcDatetime | None = None


class SettingsPatch(CamelModel):
    timezone: Annotated[str, StringConstraints(min_length=1, max_length=64)] | None = None
    correlation_window_hours: Annotated[int, Field(ge=1, le=72)] | None = None
    min_trigger_count: Annotated[int, Field(ge=1, le=20)] | None = None
    min_confidence: Annotated[int, Field(ge=0, le=100)] | None = None
    streak_meals_per_day: Annotated[int, Field(ge=1, le=6)] | None = None
    nudge_time: ClockTime | None = None
    nudges_enabled: bool | None = None
    meal_check_ins_enabled: bool | None = None
    breakfast_time: ClockTime | None = None
    lunch_time: ClockTime | None = None
    dinner_time: ClockTime | None = None


# ── Meals ───────────────────────────────────────────────────────────────────


class MealRead(CamelModel):
    id: int
    user_id: UuidStr | None = None
    name: str
    meal_type: str
    timestamp: UtcDatetime
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
    timestamp: UtcDatetime | None = None
    tz: TzName | None = None
    notes: Notes | None = None
    is_custom: bool | None = True
    ingredients: IngredientList | None = None
    ingredient_details: Annotated[list[IngredientDetail], Field(max_length=50)] | None = None
    dish_id: int | None = None
    contains_gluten: bool = False
    contains_dairy: bool = False
    contains_grains: bool = False
    contains_sugar: bool = False
    contains_nuts: bool = False


class MealPatch(CamelModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)] | None = None
    meal_type: MealTypeName | None = None
    timestamp: UtcDatetime | None = None
    tz: TzName | None = None
    notes: Notes | None = None
    ingredients: IngredientList | None = None
    ingredient_details: Annotated[list[IngredientDetail], Field(max_length=50)] | None = None
    contains_gluten: bool | None = None
    contains_dairy: bool | None = None
    contains_grains: bool | None = None
    contains_sugar: bool | None = None
    contains_nuts: bool | None = None


# ── Symptoms ────────────────────────────────────────────────────────────────


class SymptomRead(CamelModel):
    id: int
    user_id: UuidStr | None = None
    name: str
    severity: str
    intensity: int | None = None
    duration_minutes: int | None = None
    catalog_key: str | None = None
    timestamp: UtcDatetime
    notes: str | None = None
    date: str
    emoji: str | None = None
    body_region: str | None = None


class SymptomCreate(CamelModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)]
    catalog_key: Annotated[str, StringConstraints(max_length=80)] | None = None
    severity: SeverityName | None = None
    intensity: Annotated[int, Field(ge=1, le=5)] | None = None
    duration_minutes: Annotated[int, Field(ge=0, le=60 * 24 * 7)] | None = None
    timestamp: UtcDatetime | None = None
    tz: TzName | None = None
    notes: Notes | None = None

    @model_validator(mode="after")
    def _needs_a_level(self) -> "SymptomCreate":
        if self.severity is None and self.intensity is None:
            raise ValueError("Either severity or intensity is required")
        return self


class SymptomPatch(CamelModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)] | None = None
    severity: SeverityName | None = None
    intensity: Annotated[int, Field(ge=1, le=5)] | None = None
    duration_minutes: Annotated[int, Field(ge=0, le=60 * 24 * 7)] | None = None
    catalog_key: Annotated[str, StringConstraints(max_length=80)] | None = None
    timestamp: UtcDatetime | None = None
    tz: TzName | None = None
    notes: Notes | None = None


class SymptomBatchItem(CamelModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)]
    catalog_key: Annotated[str, StringConstraints(max_length=80)] | None = None
    intensity: Annotated[int, Field(ge=1, le=5)]


class SymptomBatch(CamelModel):
    timestamp: UtcDatetime | None = None
    tz: TzName | None = None
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
    user_id: UuidStr | None = None
    name: str
    emoji: str
    ingredients: list[IngredientDetail] = Field(default_factory=list)
    contains_gluten: bool | None = None
    contains_dairy: bool | None = None
    contains_grains: bool | None = None
    contains_sugar: bool | None = None
    contains_nuts: bool | None = None
    times_logged: int
    last_logged_at: UtcDatetime | None = None
    created_at: UtcDatetime | None = None
    updated_at: UtcDatetime | None = None


class DishCreate(CamelModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]
    emoji: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=16)] = "🍽️"
    ingredients: list[IngredientDetail] = Field(default_factory=list, max_length=50)
    contains_gluten: bool = False
    contains_dairy: bool = False
    contains_grains: bool = False
    contains_sugar: bool = False
    contains_nuts: bool = False


class DishPatch(CamelModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)] | None = None
    emoji: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=16)] | None = None
    ingredients: Annotated[list[IngredientDetail], Field(max_length=50)] | None = None
    contains_gluten: bool | None = None
    contains_dairy: bool | None = None
    contains_grains: bool | None = None
    contains_sugar: bool | None = None
    contains_nuts: bool | None = None


class DishLogOverrides(CamelModel):
    ingredient_details: Annotated[list[IngredientDetail], Field(max_length=50)] | None = None


class DishLog(CamelModel):
    meal_type: MealTypeName
    timestamp: UtcDatetime | None = None
    tz: str | None = None
    notes: Annotated[str, StringConstraints(max_length=2000)] | None = None
    overrides: DishLogOverrides | None = None


# ── Watchlist ───────────────────────────────────────────────────────────────


class WatchlistRead(CamelModel):
    id: int
    ingredient: str
    source: str
    created_at: UtcDatetime | None = None
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
    week_start: Annotated[str, StringConstraints(max_length=10)] | None = None
    symptom: Annotated[str, StringConstraints(max_length=80)] | None = None
    tz: TzName | None = None


class SynthesisRead(CamelModel):
    text: str
    source: Literal["claude", "rules"]
    model: str | None = None
    cached: bool
    generated_at: UtcDatetime
    suggested_watchlist: list[str] = Field(default_factory=list)


# ── Meal photo ──────────────────────────────────────────────────────────────

# base64 is 4 characters per 3 bytes, plus a little slack for padding. Pydantic
# rejecting an over-long string is cheaper than decoding it to find out.
MAX_PHOTO_B64_CHARS = 4 * ((settings.MAX_PHOTO_BYTES + 2) // 3) + 16


class MealPhotoRequest(CamelModel):
    # base64, no data-URI prefix. The ceiling here is a cheap first line of
    # defence; the decoded length is checked again, and the real media type is
    # read from the bytes rather than taken on trust.
    image_base64: Annotated[str, StringConstraints(min_length=16, max_length=MAX_PHOTO_B64_CHARS)]
    kind: Literal["meal", "label"] = "meal"
    meal_type: MealTypeName | None = None
    # Whatever the person already typed, so the model has a nudge.
    hint: Annotated[str, StringConstraints(strip_whitespace=True, max_length=120)] | None = None


class MealPhotoRead(CamelModel):
    """Deliberately the shape MealCreate accepts, so the client needs no mapping."""

    recognized: bool
    name: str = ""
    ingredients: list[IngredientDetail] = Field(default_factory=list)
    meal_category: MealTypeName | None = None
    contains_gluten: bool = False
    contains_dairy: bool = False
    contains_grains: bool = False
    contains_sugar: bool = False
    contains_nuts: bool = False
    confidence: Literal["high", "medium", "low"] = "low"
    kind: Literal["meal", "label"] = "meal"
    model: str | None = None
    # Set whenever recognized is false, so the screen always has something to say.
    message: str | None = None


# ── Waitlist ────────────────────────────────────────────────────────────────


# EmailStr lowercases the domain but leaves the local part alone, which would
# let Reader@example.com and reader@example.com both be stored and make the
# unique constraint meaningless. Every real provider treats the local part
# case-insensitively, and the Express endpoint this replaces lowercased the
# whole address, so match that.
LowercaseEmail = Annotated[
    EmailStr,
    StringConstraints(max_length=254),
    BeforeValidator(lambda v: v.strip().lower() if isinstance(v, str) else v),
]


class WaitlistRequest(CamelModel):
    # 254 is the longest an address can be, so anything beyond it is not a
    # near-miss worth accepting.
    email: LowercaseEmail
    # Honeypot. A real visitor never sees this field, so anything in it is a bot.
    company: Annotated[str, StringConstraints(max_length=200)] | None = None


class WaitlistRead(CamelModel):
    message: str
