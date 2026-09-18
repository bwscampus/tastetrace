"""Meals: the log itself."""

from fastapi import APIRouter, status
from sqlalchemy import select

from app.deps import CurrentUser, Session, TzQuery, owned_or_404, resolve_timezone
from app.models import Meal
from app.schemas import MealCreate, MealPatch, MealRead
from app.services.entries import apply_meal_timing, detail_dicts, resolve_ingredients

router = APIRouter(tags=["meals"])


@router.get("/meals", response_model=list[MealRead])
async def list_meals(user: CurrentUser, session: Session) -> list[Meal]:
    return list(
        await session.scalars(
            select(Meal).where(Meal.user_id == user.id).order_by(Meal.timestamp.desc())
        )
    )


@router.post("/meals", response_model=MealRead, status_code=status.HTTP_201_CREATED)
async def create_meal(body: MealCreate, user: CurrentUser, session: Session) -> Meal:
    tz = await resolve_timezone(session, user, body.tz)
    ingredients, details = resolve_ingredients(body.ingredient_details, body.ingredients, body.notes)

    meal = Meal(
        user_id=user.id,
        name=body.name,
        meal_type=body.meal_type,
        notes=body.notes,
        is_custom=bool(body.is_custom),
        ingredients=ingredients,
        ingredient_details=details,
        dish_id=body.dish_id,
        contains_gluten=body.contains_gluten,
        contains_dairy=body.contains_dairy,
        contains_grains=body.contains_grains,
        contains_sugar=body.contains_sugar,
        contains_nuts=body.contains_nuts,
    )
    apply_meal_timing(meal, body.timestamp, tz)
    session.add(meal)
    await session.commit()
    await session.refresh(meal)
    return meal


@router.get("/meals/{meal_id}", response_model=MealRead)
async def read_meal(meal_id: int, user: CurrentUser, session: Session) -> Meal:
    return await owned_or_404(session, Meal, meal_id, user, "Meal")


@router.put("/meals/{meal_id}", response_model=MealRead)
async def update_meal(meal_id: int, body: MealPatch, user: CurrentUser, session: Session) -> Meal:
    meal = await owned_or_404(session, Meal, meal_id, user, "Meal")
    values = body.model_dump(exclude_unset=True)

    for field in ("name", "meal_type", "notes", "contains_gluten", "contains_dairy",
                  "contains_grains", "contains_sugar", "contains_nuts"):
        if field in values:
            setattr(meal, field, values[field])

    # Editing notes must not rewrite an ingredient list the user curated.
    if body.ingredient_details is not None:
        meal.ingredient_details = detail_dicts(body.ingredient_details)
        meal.ingredients = [d.name for d in body.ingredient_details]
    elif body.ingredients is not None:
        meal.ingredients = list(body.ingredients)

    if body.timestamp is not None:
        apply_meal_timing(meal, body.timestamp, await resolve_timezone(session, user, body.tz))

    session.add(meal)
    await session.commit()
    await session.refresh(meal)
    return meal


@router.delete("/meals/{meal_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_meal(meal_id: int, user: CurrentUser, session: Session) -> None:
    meal = await owned_or_404(session, Meal, meal_id, user, "Meal")
    await session.delete(meal)
    await session.commit()
