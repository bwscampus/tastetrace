"""The screens that interpret the log: coverage, digests, triggers."""

from dataclasses import fields, is_dataclass
from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, HTTPException, Query, status
from pydantic.alias_generators import to_camel

from app.deps import CurrentUser, Session, TzQuery, get_settings_row, resolve_timezone
from app.domain.correlations import tier_for
from app.domain.coverage import compute_coverage
from app.domain.digest import compute_weekly_digest
from app.domain.flares import hours_between
from app.domain.foods import meal_items, normalize_item
from app.domain.rounding import round1, round2
from app.domain.suspects import ALL_SYMPTOMS, compute_suspects
from app.domain.time import add_days, is_iso_day, local_date
from app.services.rows import (
    correlation_row,
    load_correlations,
    load_history,
    load_meals,
    meal_row,
    settings_row,
)
from app.services.watchlist import watchlist_ingredients

router = APIRouter(tags=["analytics"])

DIMENSIONS = ("ingredient", "cook_method", "food")
# Field names the client already spells this way. The camel converter would
# mangle the digits in them ("under1h" -> "under1H"), so they pass through.
WIRE_NAME_FIELDS = frozenset({"under1h", "from1to3h", "over3h"})
# How far back a streak may reach; bounds the query, not the answer
STREAK_LOOKBACK_DAYS = 365


def camel(value: Any) -> Any:
    """Domain dataclasses to camelCase JSON.

    Only dataclass *field names* are renamed. Dictionary keys are data — the
    coverage slots ("Breakfast"), the per-slot tallies and the timing windows
    ("0to4h") are values the client looks up by name, so they are left alone.
    """
    if is_dataclass(value) and not isinstance(value, type):
        return {
            (f.name if f.name in WIRE_NAME_FIELDS else to_camel(f.name)): camel(getattr(value, f.name))
            for f in fields(value)
        }
    if isinstance(value, dict):
        return {key: camel(item) for key, item in value.items()}
    if isinstance(value, list):
        return [camel(item) for item in value]
    return value


async def _week_start(session, user, week_start: str | None, tz: str) -> str:
    if week_start in (None, ""):
        return add_days(local_date(datetime.now(UTC), tz), -6)
    if not is_iso_day(week_start):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="weekStart must be YYYY-MM-DD")
    return week_start


@router.get("/coverage")
async def coverage(
    user: CurrentUser,
    session: Session,
    date: str | None = Query(None, description="Local day, YYYY-MM-DD"),
    tz: TzQuery = None,
) -> dict:
    zone = await resolve_timezone(session, user, tz)
    day = date or local_date(datetime.now(UTC), zone)
    if not is_iso_day(day):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Date must be YYYY-MM-DD")

    settings = settings_row(await get_settings_row(session, user))
    meals = [meal_row(m) for m in await load_meals(session, user.id)]
    # Only the streak needs history; a year is further back than any streak shown
    cutoff = add_days(day, -STREAK_LOOKBACK_DAYS)
    meals = [m for m in meals if local_date(m.timestamp, zone) >= cutoff]
    return camel(compute_coverage(meals, day, zone, settings))


@router.get("/digest/weekly")
async def weekly_digest(
    user: CurrentUser,
    session: Session,
    weekStart: str | None = Query(None),  # noqa: N803 - client sends camelCase
    tz: TzQuery = None,
) -> dict:
    zone = await resolve_timezone(session, user, tz)
    start = await _week_start(session, user, weekStart, zone)
    settings = settings_row(await get_settings_row(session, user))
    meals, symptoms = await load_history(session, user.id)
    correlations = [correlation_row(c) for c in await load_correlations(session, user.id)]
    digest = compute_weekly_digest(
        meals, symptoms, correlations, start, zone, settings, local_date(datetime.now(UTC), zone)
    )
    return camel(digest)


@router.get("/digest/suspects")
async def suspects_digest(
    user: CurrentUser,
    session: Session,
    weekStart: str | None = Query(None),  # noqa: N803
    symptom: str | None = Query(None),
    tz: TzQuery = None,
) -> dict:
    zone = await resolve_timezone(session, user, tz)
    start = await _week_start(session, user, weekStart, zone)
    settings = settings_row(await get_settings_row(session, user))
    meals, symptoms = await load_history(session, user.id)
    correlations = [correlation_row(c) for c in await load_correlations(session, user.id)]
    watchlist = await watchlist_ingredients(session, user.id)

    chosen = symptom if symptom and symptom != ALL_SYMPTOMS else None
    digest = compute_suspects(
        meals, symptoms, correlations, watchlist, start, zone,
        settings.correlation_window_hours, chosen,
    )
    payload = camel(digest)
    # These window keys are data, not field names, so they keep their shape
    payload["timingWindows"] = {
        key: camel(window) for key, window in digest.timing_windows.items()
    }
    return payload


@router.get("/insights/triggers")
async def trigger_insights(
    user: CurrentUser,
    session: Session,
    dimension: str = Query("ingredient"),
    symptom: str | None = Query(None),
    minConfidence: int | None = Query(None),  # noqa: N803
) -> dict:
    from app.domain.catalog import catalog_by_key, catalog_by_name

    settings = settings_row(await get_settings_row(session, user))
    if dimension not in DIMENSIONS:
        dimension = "ingredient"
    floor = settings.min_confidence if minConfidence is None else minConfidence
    if not 0 <= floor <= 100:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="minConfidence must be 0-100")

    meals, symptoms = await load_history(session, user.id)
    rows = [correlation_row(c) for c in await load_correlations(session, user.id)]

    counts: dict[str, dict] = {}
    for entry in symptoms:
        seen = counts.setdefault(entry.name, {"key": entry.catalog_key, "count": 0})
        seen["count"] += 1
    symptom_list = [
        {
            "name": name,
            "emoji": (
                (catalog_by_key(seen["key"]) or catalog_by_name(name)).emoji
                if (catalog_by_key(seen["key"]) or catalog_by_name(name))
                else "⚡️"
            ),
            "count": seen["count"],
        }
        for name, seen in sorted(counts.items(), key=lambda kv: -kv[1]["count"])
    ]

    matching = [
        row for row in rows
        if row.dimension == dimension and (not symptom or row.symptom_name == symptom)
    ]
    visible = [row for row in matching if row.confidence >= floor]

    cards = []
    for row in visible:
        key = normalize_item(row.food_name)
        window = row.window_hours or settings.correlation_window_hours
        evidence = []
        for meal in meals:
            if not any(i.dimension == dimension and i.key == key for i in meal_items(meal)):
                continue
            for entry in symptoms:
                if entry.name != row.symptom_name:
                    continue
                onset = hours_between(meal.timestamp, entry.timestamp)
                if 0 < onset <= window:
                    evidence.append(
                        {
                            "mealId": meal.id,
                            "mealName": meal.name,
                            "mealAt": meal.timestamp,
                            "symptomAt": entry.timestamp,
                            "onsetHours": round1(onset),
                        }
                    )
        evidence.sort(key=lambda item: item["symptomAt"], reverse=True)
        cards.append(
            {
                "item": row.food_name,
                "dimension": row.dimension,
                "symptomName": row.symptom_name,
                "confidence": row.confidence,
                "tier": tier_for(row.confidence),
                "exposures": row.exposures,
                "flareExposures": row.flare_exposures,
                "hitRate": round2(row.flare_exposures / row.exposures) if row.exposures else 0,
                "baselineRate": row.baseline_rate,
                "lift": row.lift,
                "avgOnsetHours": row.avg_onset_hours,
                "lastFlareAt": row.last_flare_at,
                "evidence": evidence[:5],
            }
        )

    return {
        "dimension": dimension,
        "minConfidence": floor,
        "windowHours": settings.correlation_window_hours,
        "symptoms": symptom_list,
        "cards": cards,
        "hiddenBelowThreshold": len(matching) - len(visible),
    }
