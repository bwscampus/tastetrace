"""Bridging the database rows and the pure analytics.

The analytics take plain dataclasses, so everything that reads history goes
through here: load the user's meals and symptoms, convert, and hand them over.
"""

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.rows import IngredientRow, MealRow, SettingsRow, SymptomRow
from app.domain.rows import CorrelationRow as DomainCorrelation
from app.models import Correlation, Meal, Symptom, UserSettings


def ingredient_rows(details: list[dict] | None) -> list[IngredientRow] | None:
    if details is None:
        return None
    return [
        IngredientRow(name=item.get("name", ""), cook_method=item.get("cookMethod"))
        for item in details
    ]


def meal_row(meal: Meal) -> MealRow:
    return MealRow(
        id=meal.id,
        name=meal.name,
        meal_type=meal.meal_type,
        timestamp=meal.timestamp,
        ingredients=list(meal.ingredients or []),
        ingredient_details=ingredient_rows(meal.ingredient_details),
        notes=meal.notes,
        dish_id=meal.dish_id,
    )


def symptom_row(symptom: Symptom) -> SymptomRow:
    return SymptomRow(
        id=symptom.id,
        name=symptom.name,
        severity=symptom.severity,
        timestamp=symptom.timestamp,
        intensity=symptom.intensity,
        duration_minutes=symptom.duration_minutes,
        catalog_key=symptom.catalog_key,
        notes=symptom.notes,
    )


def correlation_row(row: Correlation) -> DomainCorrelation:
    return DomainCorrelation(
        food_name=row.food_name,
        symptom_name=row.symptom_name,
        dimension=row.dimension,
        exposures=row.exposures,
        flare_exposures=row.flare_exposures,
        occurrences=row.occurrences,
        confidence=row.confidence,
        is_ingredient=row.is_ingredient,
        baseline_rate=row.baseline_rate,
        lift=row.lift,
        avg_onset_hours=row.avg_onset_hours,
        window_hours=row.window_hours,
        last_flare_at=row.last_flare_at,
    )


def settings_row(settings: UserSettings) -> SettingsRow:
    return SettingsRow(
        timezone=settings.timezone,
        correlation_window_hours=settings.correlation_window_hours,
        min_trigger_count=settings.min_trigger_count,
        min_confidence=settings.min_confidence,
        streak_meals_per_day=settings.streak_meals_per_day,
        nudge_time=settings.nudge_time,
        nudges_enabled=settings.nudges_enabled,
        meal_check_ins_enabled=settings.meal_check_ins_enabled,
    )


async def load_meals(session: AsyncSession, user_id: UUID) -> list[Meal]:
    return list(
        await session.scalars(
            select(Meal).where(Meal.user_id == user_id).order_by(Meal.timestamp)
        )
    )


async def load_symptoms(session: AsyncSession, user_id: UUID) -> list[Symptom]:
    return list(
        await session.scalars(
            select(Symptom).where(Symptom.user_id == user_id).order_by(Symptom.timestamp)
        )
    )


async def load_correlations(session: AsyncSession, user_id: UUID) -> list[Correlation]:
    """Strongest first, which is the order the digests and insights expect."""
    return list(
        await session.scalars(
            select(Correlation)
            .where(Correlation.user_id == user_id)
            .order_by(Correlation.confidence.desc(), Correlation.flare_exposures.desc())
        )
    )


async def load_history(session: AsyncSession, user_id: UUID) -> tuple[list[MealRow], list[SymptomRow]]:
    meals = [meal_row(m) for m in await load_meals(session, user_id)]
    symptoms = [symptom_row(s) for s in await load_symptoms(session, user_id)]
    return meals, symptoms
