"""Saved dish tiles: a remembered meal, logged with one tap."""

from fastapi import APIRouter, status
from sqlalchemy import select

from app.deps import CurrentUser, Session, owned_or_404, resolve_timezone
from app.models import Dish, Meal
from app.schemas import DishCreate, DishLog, DishPatch, DishRead, MealRead
from app.services.entries import apply_meal_timing, detail_dicts, now_utc

router = APIRouter(tags=["dishes"])


@router.get("/dishes", response_model=list[DishRead])
async def list_dishes(user: CurrentUser, session: Session) -> list[Dish]:
    # Most recently used first — the tile the user wants is usually the last one
    return list(
        await session.scalars(
            select(Dish)
            .where(Dish.user_id == user.id)
            .order_by(
                Dish.last_logged_at.desc().nullslast(),
                Dish.times_logged.desc(),
                Dish.name.asc(),
            )
        )
    )


@router.post("/dishes", response_model=DishRead, status_code=status.HTTP_201_CREATED)
async def create_dish(body: DishCreate, user: CurrentUser, session: Session) -> Dish:
    dish = Dish(
        user_id=user.id,
        name=body.name,
        emoji=body.emoji,
        ingredients=detail_dicts(body.ingredients) or [],
        contains_gluten=body.contains_gluten,
        contains_dairy=body.contains_dairy,
        contains_grains=body.contains_grains,
        contains_sugar=body.contains_sugar,
        contains_nuts=body.contains_nuts,
    )
    session.add(dish)
    await session.commit()
    await session.refresh(dish)
    return dish


@router.put("/dishes/{dish_id}", response_model=DishRead)
async def update_dish(dish_id: int, body: DishPatch, user: CurrentUser, session: Session) -> Dish:
    dish = await owned_or_404(session, Dish, dish_id, user, "Dish")
    values = body.model_dump(exclude_unset=True)
    for field, value in values.items():
        if field == "ingredients":
            dish.ingredients = detail_dicts(body.ingredients) or []
        else:
            setattr(dish, field, value)
    dish.updated_at = now_utc()
    session.add(dish)
    await session.commit()
    await session.refresh(dish)
    return dish


@router.delete("/dishes/{dish_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_dish(dish_id: int, user: CurrentUser, session: Session) -> None:
    dish = await owned_or_404(session, Dish, dish_id, user, "Dish")
    # Meals logged from the tile survive; their dish_id is cleared.
    await session.delete(dish)
    await session.commit()


@router.post("/dishes/{dish_id}/log", response_model=MealRead, status_code=status.HTTP_201_CREATED)
async def log_dish(dish_id: int, body: DishLog, user: CurrentUser, session: Session) -> Meal:
    dish = await owned_or_404(session, Dish, dish_id, user, "Dish")
    tz = await resolve_timezone(session, user, body.tz)

    overrides = body.overrides.ingredient_details if body.overrides else None
    details = detail_dicts(overrides) if overrides is not None else list(dish.ingredients or [])

    meal = Meal(
        user_id=user.id,
        name=dish.name,
        meal_type=body.meal_type,
        notes=body.notes,
        is_custom=True,
        ingredients=[item.get("name", "") for item in details],
        ingredient_details=details,
        dish_id=dish.id,
        contains_gluten=dish.contains_gluten,
        contains_dairy=dish.contains_dairy,
        contains_grains=dish.contains_grains,
        contains_sugar=dish.contains_sugar,
        contains_nuts=dish.contains_nuts,
    )
    apply_meal_timing(meal, body.timestamp, tz)
    session.add(meal)

    dish.times_logged += 1
    dish.last_logged_at = meal.timestamp
    session.add(dish)

    await session.commit()
    await session.refresh(meal)
    return meal
