"""Exports: the spreadsheet, and the bundle the PDF reports render from."""

from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException, Query, Response, status
from sqlalchemy import select

from app.deps import CurrentUser, Session, TzQuery, get_settings_row, resolve_timezone
from app.domain.time import add_days, is_iso_day, local_date
from app.models import Meal, Symptom
from app.routers.analytics import camel
from app.schemas import SynthesisRead, SynthesisRequest
from app.services.export import build_ledger, dish_names, render_csv

router = APIRouter(tags=["export"])

DEFAULT_RANGE_DAYS = 30


async def _range(session, user, tz: str | None, from_: str | None, to: str | None) -> tuple[str, str, str]:
    zone = await resolve_timezone(session, user, tz)
    end = to or local_date(datetime.now(UTC), zone)
    start = from_ or add_days(end, -(DEFAULT_RANGE_DAYS - 1))
    if not is_iso_day(start) or not is_iso_day(end) or start > end:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, detail="from/to must be YYYY-MM-DD with from <= to"
        )
    return start, end, zone


@router.get("/export/csv")
async def export_csv(
    user: CurrentUser,
    session: Session,
    from_: str | None = Query(None, alias="from"),
    to: str | None = Query(None),
    tz: TzQuery = None,
) -> Response:
    start, end, zone = await _range(session, user, tz, from_, to)

    meals = list(
        await session.scalars(select(Meal).where(Meal.user_id == user.id).order_by(Meal.timestamp))
    )
    symptoms = list(
        await session.scalars(select(Symptom).where(Symptom.user_id == user.id).order_by(Symptom.timestamp))
    )
    in_range = lambda row: start <= local_date(row.timestamp, zone) <= end  # noqa: E731

    body = render_csv(
        [m for m in meals if in_range(m)],
        [s for s in symptoms if in_range(s)],
        await dish_names(session, user.id),
        zone,
    )
    return Response(
        content=body,
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="tastetrace-{start}-{end}.csv"'},
    )


@router.get("/export/ledger")
async def export_ledger(
    user: CurrentUser,
    session: Session,
    from_: str | None = Query(None, alias="from"),
    to: str | None = Query(None),
    tz: TzQuery = None,
) -> dict:
    start, end, zone = await _range(session, user, tz, from_, to)
    settings = await get_settings_row(session, user)
    bundle = await build_ledger(session, user, settings, start, end, zone)

    payload = camel(bundle)
    # The range keys are data the client reads by name
    payload["range"] = {"from": start, "to": end, "tz": zone}
    return payload
