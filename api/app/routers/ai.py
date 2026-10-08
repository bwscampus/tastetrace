"""The AI summary on the Food Suspect Digest, and reading a meal photo."""

import logging
import time
from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException, Request, status

from app.ai import photo as photo_ai
from app.ai.synthesis import synthesize
from app.ai.throttle import DailyQuota
from app.config import settings as app_settings  # the route below shadows `settings`
from app.deps import CurrentUser, Session, get_settings_row, resolve_timezone
from app.domain.suspects import ALL_SYMPTOMS, compute_suspects
from app.domain.time import add_days, is_iso_day, local_date
from app.schemas import MealPhotoRead, MealPhotoRequest, SynthesisRead, SynthesisRequest
from app.services.rows import correlation_row, load_correlations, load_history, settings_row
from app.services.watchlist import watchlist_ingredients

logger = logging.getLogger("app.ai")

router = APIRouter(tags=["ai"])

daily_quota = DailyQuota(lambda: app_settings.PHOTO_DAILY_LIMIT)


@router.post("/ai/synthesis", response_model=SynthesisRead)
async def synthesis(body: SynthesisRequest, user: CurrentUser, session: Session) -> dict:
    zone = await resolve_timezone(session, user, body.tz)
    week_start = body.week_start or add_days(local_date(datetime.now(UTC), zone), -6)
    if not is_iso_day(week_start):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="weekStart must be YYYY-MM-DD")

    chosen = body.symptom if body.symptom and body.symptom != ALL_SYMPTOMS else None
    settings = await get_settings_row(session, user)
    meals, symptoms = await load_history(session, user.id)
    correlations = [correlation_row(c) for c in await load_correlations(session, user.id)]
    watchlist = await watchlist_ingredients(session, user.id)

    suspects = compute_suspects(
        meals, symptoms, correlations, watchlist, week_start, zone,
        settings.correlation_window_hours, chosen,
    )
    return await synthesize(session, user.id, suspects, chosen)


@router.post("/ai/meal-photo", response_model=MealPhotoRead)
async def meal_photo(body: MealPhotoRequest, request: Request, user: CurrentUser) -> dict:
    """Read a plate or an ingredient label into the fields a meal needs.

    Takes no database session, deliberately: nothing about the photo is stored,
    and a route that cannot reach the database cannot store it by accident. The
    person confirms the result in the editor, and the ordinary meal endpoint
    writes it.

    A model-side failure answers 200 with recognized false and a message, because
    the screen must always have something to show. Only the guards below, which
    happen before the model is reached, answer an error status.
    """
    if not (app_settings.PHOTO_RECOGNITION_ENABLED and app_settings.OPENAI_API_KEY):
        # 503 rather than an unmounted route: a shipped build has to tell
        # "switched off" apart from "talking to an older server", and a 404
        # cannot say which.
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, detail=photo_ai.UNAVAILABLE
        )

    # Cheapest check first: the declared length, before anything is decoded.
    declared = request.headers.get("content-length")
    if declared is None:
        raise HTTPException(
            status.HTTP_411_LENGTH_REQUIRED, detail="Send the photo with a Content-Length."
        )
    if declared.isdigit() and int(declared) > app_settings.MAX_PHOTO_BYTES * 2:
        megabytes = app_settings.MAX_PHOTO_BYTES / (1024 * 1024)
        raise HTTPException(
            status.HTTP_413_CONTENT_TOO_LARGE,
            detail=f"That photo is larger than {megabytes:.0f} MB.",
        )

    now = time.monotonic()
    today = datetime.now(UTC).strftime("%Y-%m-%d")
    if photo_ai.throttle.is_throttled(user.id, now):
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Give it a few seconds before reading another photo.",
            headers={"Retry-After": str(photo_ai.throttle.retry_after(user.id, now))},
        )
    if daily_quota.exhausted(user.id, today):
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            detail="That's today's limit for reading photos. Type the meal in instead.",
        )

    try:
        raw, media_type = photo_ai.decode_image(body.image_base64)
    except photo_ai.PhotoRejected as rejected:
        raise HTTPException(rejected.status_code, detail=rejected.detail) from rejected

    photo_ai.throttle.record(user.id, now)
    daily_quota.record(user.id, today)

    started = time.monotonic()
    result = await photo_ai.read_photo(
        raw, media_type, kind=body.kind, meal_type=body.meal_type, hint=body.hint
    )
    # Size, type, outcome and latency only. Never the image, never the food:
    # what someone eats is health data and does not belong in a log line.
    logger.info(
        "Photo read: %s, %s, %d bytes, recognized=%s, %d ingredients, %.0fms",
        body.kind,
        media_type,
        len(raw),
        result.recognized,
        len(result.ingredients),
        (time.monotonic() - started) * 1000,
    )

    return {
        "recognized": result.recognized,
        "name": result.name,
        "ingredients": result.ingredients,
        "meal_category": result.meal_category,
        "contains_gluten": result.contains_gluten,
        "contains_dairy": result.contains_dairy,
        "contains_grains": result.contains_grains,
        "contains_sugar": result.contains_sugar,
        "contains_nuts": result.contains_nuts,
        "confidence": result.confidence,
        "kind": body.kind,
        "model": result.model,
        "message": result.message,
    }
