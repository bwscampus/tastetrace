"""The AI summary on the Food Suspect Digest."""

from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException, status

from app.ai.synthesis import synthesize
from app.deps import CurrentUser, Session, get_settings_row, resolve_timezone
from app.domain.suspects import ALL_SYMPTOMS, compute_suspects
from app.domain.time import add_days, is_iso_day, local_date
from app.schemas import SynthesisRead, SynthesisRequest
from app.services.rows import correlation_row, load_correlations, load_history, settings_row
from app.services.watchlist import watchlist_ingredients

router = APIRouter(tags=["ai"])


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
