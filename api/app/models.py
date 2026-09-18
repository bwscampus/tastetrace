"""Project tables.

Auth tables live in app/auth/models.py — keeping them apart is what lets a
template update land without touching project migrations (references/schema.md).

Conventions here:
- `user_id` is the fastapi-users UUID; every query must filter on it.
- Meals, symptoms, dishes and watchlist rows keep integer primary keys
  because the iOS client decodes them as `Int`.
- `date` is the *local* calendar day (YYYY-MM-DD) the entry belongs to,
  derived server-side from `timestamp` in the user's timezone. Analytics
  bucket by it, so it is never taken from the client.
"""

from datetime import UTC, datetime

from fastapi_users_db_sqlalchemy.generics import GUID
from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base, JSONDocument


def _now() -> datetime:
    return datetime.now(UTC)


class UserSettings(Base):
    """One row per user; created with defaults on first read."""

    __tablename__ = "user_settings"

    user_id: Mapped[GUID] = mapped_column(
        GUID, ForeignKey("users.id", ondelete="cascade"), primary_key=True
    )
    timezone: Mapped[str] = mapped_column(Text, nullable=False, default="UTC")
    # How long after a meal a symptom still counts as following it
    correlation_window_hours: Mapped[int] = mapped_column(Integer, nullable=False, default=24)
    # Flares needed before an item may pass the confidence floor
    min_trigger_count: Mapped[int] = mapped_column(Integer, nullable=False, default=2)
    min_confidence: Mapped[int] = mapped_column(Integer, nullable=False, default=50)
    streak_meals_per_day: Mapped[int] = mapped_column(Integer, nullable=False, default=2)
    nudge_time: Mapped[str] = mapped_column(Text, nullable=False, default="20:30")
    nudges_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    meal_check_ins_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, default=_now
    )


class Dish(Base):
    """A saved dish tile: remembered ingredients for one-tap logging."""

    __tablename__ = "dishes"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[GUID] = mapped_column(
        GUID, ForeignKey("users.id", ondelete="cascade"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(Text, nullable=False)
    emoji: Mapped[str] = mapped_column(String(16), nullable=False, default="🍽️")
    # [{name, cookMethod?}]
    ingredients: Mapped[list[dict]] = mapped_column(JSONDocument, nullable=False, default=list)
    contains_gluten: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    contains_dairy: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    contains_grains: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    contains_sugar: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    contains_nuts: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    times_logged: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    last_logged_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=_now)


class Meal(Base):
    __tablename__ = "meals"
    __table_args__ = (Index("ix_meals_user_timestamp", "user_id", "timestamp"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[GUID] = mapped_column(
        GUID, ForeignKey("users.id", ondelete="cascade"), nullable=False
    )
    name: Mapped[str] = mapped_column(Text, nullable=False)
    meal_type: Mapped[str] = mapped_column(Text, nullable=False)
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=_now)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_custom: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    # Plain names, kept in step with ingredient_details for analytics and CSV
    ingredients: Mapped[list[str]] = mapped_column(JSONDocument, nullable=False, default=list)
    # [{name, cookMethod?}] — null on rows logged without the detail editor
    ingredient_details: Mapped[list[dict] | None] = mapped_column(JSONDocument, nullable=True)
    dish_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("dishes.id", ondelete="SET NULL"), nullable=True
    )
    contains_gluten: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    contains_dairy: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    contains_grains: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    contains_sugar: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    contains_nuts: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    date: Mapped[str] = mapped_column(String(10), nullable=False)


class Symptom(Base):
    __tablename__ = "symptoms"
    __table_args__ = (Index("ix_symptoms_user_timestamp", "user_id", "timestamp"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[GUID] = mapped_column(
        GUID, ForeignKey("users.id", ondelete="cascade"), nullable=False
    )
    name: Mapped[str] = mapped_column(Text, nullable=False)
    # Both levels are always stored: the 1-5 scale the app uses and the
    # Mild/Moderate/Severe wording, derived from each other when missing.
    severity: Mapped[str] = mapped_column(Text, nullable=False)
    intensity: Mapped[int | None] = mapped_column(Integer, nullable=True)
    duration_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    catalog_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=_now)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    date: Mapped[str] = mapped_column(String(10), nullable=False)


class CustomSymptom(Base):
    """A symptom the user added beyond the built-in catalog."""

    __tablename__ = "custom_symptoms"
    __table_args__ = (UniqueConstraint("user_id", "key", name="uq_custom_symptoms_user_key"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[GUID] = mapped_column(
        GUID, ForeignKey("users.id", ondelete="cascade"), nullable=False
    )
    key: Mapped[str] = mapped_column(Text, nullable=False)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    emoji: Mapped[str] = mapped_column(String(16), nullable=False, default="🩺")
    body_region: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=_now)


class Correlation(Base):
    """One (item, symptom) association, rebuilt wholesale on every recompute."""

    __tablename__ = "correlations"
    __table_args__ = (Index("ix_correlations_user", "user_id"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[GUID] = mapped_column(
        GUID, ForeignKey("users.id", ondelete="cascade"), nullable=False
    )
    food_name: Mapped[str] = mapped_column(Text, nullable=False)
    symptom_name: Mapped[str] = mapped_column(Text, nullable=False)
    dimension: Mapped[str] = mapped_column(Text, nullable=False, default="food")
    # Meals containing the item, and how many were followed by the symptom
    exposures: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    flare_exposures: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    occurrences: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    confidence: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    is_ingredient: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    baseline_rate: Mapped[float | None] = mapped_column(Float, nullable=True)
    lift: Mapped[float | None] = mapped_column(Float, nullable=True)
    avg_onset_hours: Mapped[float | None] = mapped_column(Float, nullable=True)
    window_hours: Mapped[int | None] = mapped_column(Integer, nullable=True)
    last_flare_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=_now)


class WatchlistItem(Base):
    """An ingredient the user is monitoring; matched while logging a meal."""

    __tablename__ = "watchlist"
    __table_args__ = (UniqueConstraint("user_id", "ingredient", name="uq_watchlist_user_ingredient"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[GUID] = mapped_column(
        GUID, ForeignKey("users.id", ondelete="cascade"), nullable=False
    )
    ingredient: Mapped[str] = mapped_column(Text, nullable=False)  # normalised lowercase
    source: Mapped[str] = mapped_column(Text, nullable=False, default="manual")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=_now)


class AiSynthesis(Base):
    """Cached AI summary, keyed by a hash of the data it described."""

    __tablename__ = "ai_syntheses"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "kind", "week_start", "symptom_filter", name="uq_ai_synthesis_key"
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[GUID] = mapped_column(
        GUID, ForeignKey("users.id", ondelete="cascade"), nullable=False
    )
    kind: Mapped[str] = mapped_column(Text, nullable=False)
    week_start: Mapped[str] = mapped_column(String(10), nullable=False)
    symptom_filter: Mapped[str] = mapped_column(Text, nullable=False, default="")
    input_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    source: Mapped[str] = mapped_column(Text, nullable=False)
    model: Mapped[str | None] = mapped_column(Text, nullable=True)
    text: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=_now)
