"""Dependencies shared by the project routers.

The rule that matters here: an authenticated user is not an authorised one.
Every project query filters on `user.id`, and a row belonging to someone else
is reported as 404 (never 403) so the API never confirms it exists.
"""

from typing import Annotated
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.models import User
from app.auth.router import current_active_user
from app.db import get_async_session
from app.models import UserSettings

CurrentUser = Annotated[User, Depends(current_active_user)]
Session = Annotated[AsyncSession, Depends(get_async_session)]


def is_valid_timezone(name: str | None) -> bool:
    if not name:
        return False
    try:
        ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError):
        return False
    return True


async def get_settings_row(session: AsyncSession, user: User) -> UserSettings:
    """The user's settings, created with defaults on first use."""
    row = await session.get(UserSettings, user.id)
    if row is None:
        row = UserSettings(user_id=user.id)
        session.add(row)
        await session.flush()
    return row


async def resolve_timezone(
    session: AsyncSession, user: User, requested: str | None = None
) -> str:
    """An explicit `tz` wins; otherwise the user's saved timezone.

    Entries are bucketed into local calendar days, so this decides which day a
    meal or symptom belongs to.
    """
    if is_valid_timezone(requested):
        return requested  # type: ignore[return-value]
    settings_row = await get_settings_row(session, user)
    return settings_row.timezone


def not_found(what: str) -> HTTPException:
    return HTTPException(status.HTTP_404_NOT_FOUND, detail=f"{what} not found")


async def owned_or_404(session: AsyncSession, model, row_id: int, user: User, what: str):
    """Fetches a row by id, scoped to the user."""
    row = await session.scalar(
        select(model).where(model.id == row_id, model.user_id == user.id)
    )
    if row is None:
        raise not_found(what)
    return row


TzQuery = Annotated[str | None, Query(description="IANA timezone, e.g. America/Los_Angeles")]
