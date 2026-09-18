"""Watchlist entries, and how confident we are about each one."""

from fastapi import APIRouter, status
from sqlalchemy import select

from app.deps import CurrentUser, Session, owned_or_404
from app.domain.foods import normalize_item
from app.models import WatchlistItem
from app.schemas import WatchlistCreate, WatchlistRead
from app.services.rows import load_correlations
from app.services.watchlist import add_watchlist_item

router = APIRouter(tags=["watchlist"])


@router.get("/watchlist", response_model=list[WatchlistRead])
async def list_watchlist(user: CurrentUser, session: Session) -> list[dict]:
    items = list(
        await session.scalars(
            select(WatchlistItem)
            .where(WatchlistItem.user_id == user.id)
            .order_by(WatchlistItem.created_at.desc())
        )
    )
    correlations = await load_correlations(session, user.id)
    return [
        {
            "id": item.id,
            "ingredient": item.ingredient,
            "source": item.source,
            "created_at": item.created_at,
            "confidence_max": max(
                (c.confidence for c in correlations if normalize_item(c.food_name) == item.ingredient),
                default=0,
            ),
        }
        for item in items
    ]


@router.post("/watchlist", response_model=WatchlistRead, status_code=status.HTTP_201_CREATED)
async def add_to_watchlist(body: WatchlistCreate, user: CurrentUser, session: Session) -> dict:
    row = await add_watchlist_item(session, user.id, body.ingredient, body.source)
    await session.commit()
    await session.refresh(row)
    return {
        "id": row.id,
        "ingredient": row.ingredient,
        "source": row.source,
        "created_at": row.created_at,
        "confidence_max": 0,
    }


@router.delete("/watchlist/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_from_watchlist(item_id: int, user: CurrentUser, session: Session) -> None:
    row = await owned_or_404(session, WatchlistItem, item_id, user, "Watchlist item")
    await session.delete(row)
    await session.commit()
