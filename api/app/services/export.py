"""Taking the journal out: a spreadsheet, or a bundle for the PDF reports."""

from datetime import UTC, datetime
from uuid import UUID

from pydantic.alias_generators import to_camel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.models import User
from app.domain.correlations import suspicion_for, tier_for
from app.domain.digest import compute_weekly_digest
from app.domain.flares import cluster_flares
from app.domain.time import add_days, local_date, local_time
from app.models import CustomSymptom, Dish, Meal, Symptom, UserSettings
from app.services.rows import (
    correlation_row,
    load_correlations,
    load_history,
    meal_row,
    settings_row,
    symptom_row,
)

CSV_HEADER = (
    "entry_type,id,date,time,name,meal_type,ingredients,cook_methods,dish,"
    "intensity,severity,duration_minutes,notes,timestamp_utc"
)
MAX_LEDGER_WEEKS = 8


def csv_cell(value: object) -> str:
    """Quote only when the cell would otherwise break the row."""
    if value is None:
        return ""
    text = str(value)
    if any(ch in text for ch in ('"', ",", "\n")):
        return '"' + text.replace('"', '""') + '"'
    return text


def csv_rows(
    meals: list[Meal], symptoms: list[Symptom], dish_names: dict[int, str], tz: str
) -> list[list[object]]:
    rows: list[list[object]] = []
    for meal in meals:
        details = meal.ingredient_details or [{"name": name} for name in (meal.ingredients or [])]
        rows.append(
            [
                "meal", meal.id, local_date(meal.timestamp, tz), local_time(meal.timestamp, tz),
                meal.name, meal.meal_type,
                "; ".join(item.get("name", "") for item in details),
                "; ".join(item.get("cookMethod") or "" for item in details),
                dish_names.get(meal.dish_id, "") if meal.dish_id else "",
                "", "", "", meal.notes or "", _iso(meal.timestamp),
            ]
        )
    for symptom in symptoms:
        rows.append(
            [
                "symptom", symptom.id, local_date(symptom.timestamp, tz),
                local_time(symptom.timestamp, tz), symptom.name, "", "", "", "",
                symptom.intensity if symptom.intensity is not None else "",
                symptom.severity,
                symptom.duration_minutes if symptom.duration_minutes is not None else "",
                symptom.notes or "", _iso(symptom.timestamp),
            ]
        )
    rows.sort(key=lambda row: str(row[13]))
    return rows


def columns_of(row) -> dict:
    """An ORM row as a plain camelCase dict, ready for the client."""
    return {
        to_camel(column.name): getattr(row, column.name)
        for column in type(row).__table__.columns
    }


def _iso(value: datetime) -> str:
    utc = value.astimezone(UTC) if value.tzinfo else value.replace(tzinfo=UTC)
    return f"{utc:%Y-%m-%dT%H:%M:%S}.{utc.microsecond // 1000:03d}Z"


def render_csv(meals: list[Meal], symptoms: list[Symptom], dish_names: dict[int, str], tz: str) -> str:
    rows = csv_rows(meals, symptoms, dish_names, tz)
    lines = [CSV_HEADER, *(",".join(csv_cell(cell) for cell in row) for row in rows)]
    return "\n".join(lines) + "\n"


async def build_ledger(
    session: AsyncSession, user: User, settings: UserSettings, from_day: str, to_day: str, tz: str
) -> dict:
    """Everything the on-device PDF reports render, for one date range."""
    meals_all, symptoms_all = await load_history(session, user.id)
    correlations = [correlation_row(c) for c in await load_correlations(session, user.id)]

    meal_rows = list(
        await session.scalars(select(Meal).where(Meal.user_id == user.id).order_by(Meal.timestamp))
    )
    symptom_rows = list(
        await session.scalars(select(Symptom).where(Symptom.user_id == user.id).order_by(Symptom.timestamp))
    )
    in_range = lambda row: from_day <= local_date(row.timestamp, tz) <= to_day  # noqa: E731
    meals = [m for m in meal_rows if in_range(m)]
    symptoms = [s for s in symptom_rows if in_range(s)]

    days: dict[str, dict] = {}
    for meal in meals:
        day = days.setdefault(
            local_date(meal.timestamp, tz),
            {"date": local_date(meal.timestamp, tz), "meals": [], "symptoms": [], "flares": 0},
        )
        suspicious_for, suspicion = suspicion_for(
            meal_row(meal), symptoms_all, correlations,
            settings.correlation_window_hours, settings.min_confidence,
        )
        day["meals"].append(
            {**columns_of(meal), "suspiciousFor": suspicious_for, "suspicion": suspicion}
        )
    for symptom in symptoms:
        day = days.setdefault(
            local_date(symptom.timestamp, tz),
            {"date": local_date(symptom.timestamp, tz), "meals": [], "symptoms": [], "flares": 0},
        )
        day["symptoms"].append(columns_of(symptom))
    for date, day in days.items():
        day["flares"] = len(
            cluster_flares([symptom_row(s) for s in symptoms if local_date(s.timestamp, tz) == date])
        )

    today = local_date(datetime.now(UTC), tz)
    weeks = []
    week_start = add_days(to_day, -6)
    while week_start >= add_days(from_day, -6) and len(weeks) < MAX_LEDGER_WEEKS:
        weeks.append(
            compute_weekly_digest(
                meals_all, symptoms_all, correlations, week_start, tz, settings_row(settings), today
            )
        )
        week_start = add_days(week_start, -7)

    custom = list(await session.scalars(select(CustomSymptom).where(CustomSymptom.user_id == user.id)))
    return {
        "generatedAt": datetime.now(UTC),
        "profile": {
            "id": str(user.id),
            "email": user.email,
            "firstName": user.first_name,
            "lastName": user.last_name,
            "displayName": user.display_name,
            "discoveryPurpose": user.discovery_purpose,
            "sensitivityTags": user.sensitivity_tags or [],
        },
        "settings": {k: v for k, v in columns_of(settings).items() if k != "userId"},
        "range": {"from": from_day, "to": to_day, "tz": tz},
        "totals": {"meals": len(meals), "symptoms": len(symptoms), "days": len(days)},
        "days": [days[date] for date in sorted(days)],
        "triggers": [
            {
                "foodName": row.food_name,
                "symptomName": row.symptom_name,
                "dimension": row.dimension,
                "confidence": row.confidence,
                "tier": tier_for(row.confidence),
                "exposures": row.exposures,
                "flareExposures": row.flare_exposures,
                "avgOnsetHours": row.avg_onset_hours,
            }
            for row in correlations
            if row.confidence >= settings.min_confidence
        ],
        "customSymptoms": [columns_of(row) for row in custom],
        "digestWeeks": weeks,
    }


async def dish_names(session: AsyncSession, user_id: UUID) -> dict[int, str]:
    rows = await session.scalars(select(Dish).where(Dish.user_id == user_id))
    return {dish.id: dish.name for dish in rows}
