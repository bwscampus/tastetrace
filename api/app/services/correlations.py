"""Placeholder until the domain port lands (P2)."""

from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession


async def recompute_correlations(session: AsyncSession, user_id: UUID) -> None:
    return None
