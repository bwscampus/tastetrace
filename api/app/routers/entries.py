"""What was logged on a day, and the dots the calendar shows."""

from datetime import timedelta

from fastapi import APIRouter, HTTPException, Query, status
from sqlalchemy import select

from app.deps import CurrentUser, Session, TzQuery, get_settings_row, resolve_timezone
from app.domain.correlations import suspicion_for
from app.domain.flares import cluster_flares
from app.domain.time import day_bounds, is_iso_day, local_date, parse_instant_or_none
from app.models import Meal, Symptom
from app.schemas import DayEntries, DayMarker
from app.services.entries import present_symptom
from app.services.rows import correlation_row, load_correlations, meal_row, symptom_row

router = APIRouter(tags=["entries"])


@router.get("/entries/date", response_model=DayEntries)
async def entries_for_day(
    user: CurrentUser,
    session: Session,
    date: str = Query(..., description="Local day, YYYY-MM-DD"),
    tz: TzQuery = None,
) -> dict:
    if not is_iso_day(date):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Date must be YYYY-MM-DD")

    settings = await get_settings_row(session, user)
    zone = await resolve_timezone(session, user, tz)
    start, end = day_bounds(date, zone)

    meals = list(
        await session.scalars(
            select(Meal)
            .where(Meal.user_id == user.id, Meal.timestamp >= start, Meal.timestamp < end)
            .order_by(Meal.timestamp)
        )
    )
    symptoms = list(
        await session.scalars(
            select(Symptom)
            .where(Symptom.user_id == user.id, Symptom.timestamp >= start, Symptom.timestamp < end)
            .order_by(Symptom.timestamp)
        )
    )

    # A meal late in the day can be followed by a symptom after midnight, so
    # look forward a whole correlation window when deciding what to flag.
    follow_up = end + timedelta(hours=settings.correlation_window_hours)
    later = list(
        await session.scalars(
            select(Symptom)
            .where(Symptom.user_id == user.id, Symptom.timestamp >= start, Symptom.timestamp <= follow_up)
            .order_by(Symptom.timestamp)
        )
    )
    later_rows = [symptom_row(s) for s in later]
    correlations = [correlation_row(c) for c in await load_correlations(session, user.id)]

    meal_payloads = []
    for meal in meals:
        suspicious_for, suspicion = suspicion_for(
            meal_row(meal),
            later_rows,
            correlations,
            settings.correlation_window_hours,
            settings.min_confidence,
        )
        meal_payloads.append(
            {
                **{c.name: getattr(meal, c.name) for c in Meal.__table__.columns},
                "suspicious_for": suspicious_for,
                "suspicion": suspicion,
            }
        )

    symptom_payloads = [
        {
            **{c.name: getattr(symptom, c.name) for c in Symptom.__table__.columns},
            **present_symptom(symptom, {}),
        }
        for symptom in symptoms
    ]

    return {
        "date": date,
        "meals": meal_payloads,
        "symptoms": symptom_payloads,
        "flares": len(cluster_flares([symptom_row(s) for s in symptoms])),
        "entries": len(meals) + len(symptoms),
    }


@router.get("/entries/markers", response_model=dict[str, DayMarker])
async def entry_markers(
    user: CurrentUser,
    session: Session,
    start: str = Query(..., description="ISO instant"),
    end: str = Query(..., description="ISO instant"),
    tz: TzQuery = None,
) -> dict[str, dict]:
    start_at, end_at = parse_instant_or_none(start), parse_instant_or_none(end)
    if start_at is None or end_at is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Start and end must be ISO dates")

    zone = await resolve_timezone(session, user, tz)
    meals = await session.scalars(
        select(Meal).where(Meal.user_id == user.id, Meal.timestamp >= start_at, Meal.timestamp <= end_at)
    )
    symptoms = await session.scalars(
        select(Symptom).where(
            Symptom.user_id == user.id, Symptom.timestamp >= start_at, Symptom.timestamp <= end_at
        )
    )

    markers: dict[str, dict] = {}

    def bucket(day: str) -> dict:
        return markers.setdefault(day, {"meals": 0, "symptoms": 0, "max_intensity": 0, "status": "ok"})

    for meal in meals:
        bucket(local_date(meal.timestamp, zone))["meals"] += 1
    for symptom in symptoms:
        marker = bucket(local_date(symptom.timestamp, zone))
        marker["symptoms"] += 1
        marker["max_intensity"] = max(marker["max_intensity"], symptom.intensity or 0)

    for marker in markers.values():
        marker["status"] = (
            "symptom" if marker["symptoms"] else "meal" if marker["meals"] else "ok"
        )
    return markers
