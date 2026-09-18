"""The ingredients a user is keeping an eye on."""

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.foods import normalize_item
from app.models import WatchlistItem


async def watchlist_ingredients(session: AsyncSession, user_id: UUID) -> list[str]:
    rows = await session.scalars(
        select(WatchlistItem.ingredient).where(WatchlistItem.user_id == user_id)
    )
    return list(rows)


async def add_watchlist_item(
    session: AsyncSession, user_id: UUID, ingredient: str, source: str
) -> WatchlistItem:
    """Stored normalised, so "Sourdough Bread" and "sourdough  bread" are one entry."""
    name = normalize_item(ingredient)
    existing = await session.scalar(
        select(WatchlistItem).where(
            WatchlistItem.user_id == user_id, WatchlistItem.ingredient == name
        )
    )
    row = existing or WatchlistItem(user_id=user_id, ingredient=name)
    row.source = source
    session.add(row)
    return row
