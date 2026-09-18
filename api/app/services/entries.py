"""Writing meals and symptoms.

Two rules live here rather than in the routers, because every path that
creates an entry must follow them:

- the local day is derived from the timestamp and the timezone, never taken
  from the client, since the analytics bucket by it;
- a symptom always ends up with both an intensity and a severity.
"""

from datetime import UTC, datetime

from app.domain.catalog import catalog_by_name, custom_symptom_key
from app.domain.severity import severity_fields
from app.domain.time import local_date
from app.models import Meal, Symptom
from app.schemas import IngredientDetail


def now_utc() -> datetime:
    return datetime.now(UTC)


def detail_dicts(details: list[IngredientDetail] | None) -> list[dict] | None:
    """Stored camelCase so the JSON column round-trips to the client as-is."""
    if details is None:
        return None
    return [{"name": d.name, "cookMethod": d.cook_method} for d in details]


def ingredients_from_notes(notes: str) -> list[str]:
    """Last resort for meals logged without an ingredient list."""
    parts = [part.strip() for part in notes.replace("\n", ",").replace(";", ",").split(",")]
    return [part for part in parts if part]


def resolve_ingredients(
    details: list[IngredientDetail] | None,
    ingredients: list[str] | None,
    notes: str | None,
) -> tuple[list[str], list[dict] | None]:
    """The detailed list wins and defines the plain names; otherwise the plain
    list; otherwise whatever the notes look like."""
    if details is not None:
        return [d.name for d in details], detail_dicts(details)
    if ingredients is not None:
        return list(ingredients), None
    if notes:
        return ingredients_from_notes(notes), None
    return [], None


def apply_meal_timing(meal: Meal, timestamp: datetime | None, tz: str) -> None:
    meal.timestamp = timestamp or now_utc()
    meal.date = local_date(meal.timestamp, tz)


def symptom_values(
    name: str,
    severity: str | None,
    intensity: int | None,
    catalog_key: str | None,
    timestamp: datetime | None,
    tz: str,
) -> dict:
    """The stored shape of a symptom, with both scales and a catalog key."""
    resolved_severity, resolved_intensity = severity_fields(severity, intensity)
    when = timestamp or now_utc()
    catalog = catalog_by_name(name)
    return {
        "name": name,
        "severity": resolved_severity,
        "intensity": resolved_intensity,
        "catalog_key": catalog_key or (catalog.key if catalog else custom_symptom_key(name)),
        "timestamp": when,
        "date": local_date(when, tz),
    }


def present_symptom(symptom: Symptom, custom: dict[str, tuple[str, str | None]]) -> dict:
    """Adds the emoji and body region the app shows beside a symptom."""
    entry = catalog_by_name(symptom.name)
    emoji = entry.emoji if entry else None
    region = entry.body_region if entry else None
    if symptom.catalog_key in custom:
        emoji, region = custom[symptom.catalog_key]
    return {"emoji": emoji, "body_region": region}
