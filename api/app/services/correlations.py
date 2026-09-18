"""Recomputing a user's associations.

Every symptom write changes the picture, so the rows are rebuilt from the
whole history and replaced in one transaction: partial state would surface as
wrong confidence numbers on the next screen.
"""

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.deps import get_settings_row_by_id
from app.domain.correlations import compute_correlations
from app.models import Correlation
from app.services.rows import load_history, settings_row

INSERT_CHUNK = 200


async def recompute_correlations(session: AsyncSession, user_id: UUID) -> None:
    meals, symptoms = await load_history(session, user_id)
    settings = settings_row(await get_settings_row_by_id(session, user_id))
    rows = compute_correlations(meals, symptoms, settings)

    await session.execute(delete(Correlation).where(Correlation.user_id == user_id))
    now = datetime.now(UTC)
    for start in range(0, len(rows), INSERT_CHUNK):
        session.add_all(
            [
                Correlation(
                    user_id=user_id,
                    food_name=row.food_name,
                    symptom_name=row.symptom_name,
                    dimension=row.dimension,
                    exposures=row.exposures,
                    flare_exposures=row.flare_exposures,
                    occurrences=row.occurrences,
                    confidence=row.confidence,
                    is_ingredient=row.is_ingredient,
                    baseline_rate=row.baseline_rate,
                    lift=row.lift,
                    avg_onset_hours=row.avg_onset_hours,
                    window_hours=row.window_hours,
                    last_flare_at=row.last_flare_at,
                    updated_at=now,
                )
                for row in rows[start : start + INSERT_CHUNK]
            ]
        )
    await session.flush()
