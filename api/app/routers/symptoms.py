"""Symptoms, the batch the Quick Log grid posts, and the symptom catalog."""

from fastapi import APIRouter, status
from sqlalchemy import select

from app.deps import CurrentUser, Session, owned_or_404, resolve_timezone
from app.domain.catalog import SYMPTOM_CATALOG, custom_symptom_key
from app.models import CustomSymptom, Symptom
from app.schemas import (
    CatalogItem,
    CustomSymptomCreate,
    CustomSymptomRead,
    SymptomBatch,
    SymptomCatalogRead,
    SymptomCreate,
    SymptomPatch,
    SymptomRead,
)
from app.services.correlations import recompute_correlations
from app.services.entries import present_symptom, symptom_values
from app.services.rows import load_symptoms

router = APIRouter(tags=["symptoms"])


async def _custom_lookup(session, user) -> dict[str, tuple[str, str | None]]:
    rows = await session.scalars(select(CustomSymptom).where(CustomSymptom.user_id == user.id))
    return {row.key: (row.emoji, row.body_region) for row in rows}


async def _present(session, user, symptom: Symptom) -> dict:
    custom = await _custom_lookup(session, user)
    return {
        **{c.name: getattr(symptom, c.name) for c in Symptom.__table__.columns},
        **present_symptom(symptom, custom),
    }


@router.get("/symptoms", response_model=list[SymptomRead])
async def list_symptoms(user: CurrentUser, session: Session) -> list[Symptom]:
    return await load_symptoms(session, user.id)


@router.post("/symptoms", response_model=SymptomRead, status_code=status.HTTP_201_CREATED)
async def create_symptom(body: SymptomCreate, user: CurrentUser, session: Session) -> dict:
    tz = await resolve_timezone(session, user, body.tz)
    symptom = Symptom(
        user_id=user.id,
        notes=body.notes,
        duration_minutes=body.duration_minutes,
        **symptom_values(body.name, body.severity, body.intensity, body.catalog_key, body.timestamp, tz),
    )
    session.add(symptom)
    await session.flush()
    # A new symptom changes every association, so the next read sees fresh rows.
    await recompute_correlations(session, user.id)
    await session.commit()
    await session.refresh(symptom)
    return await _present(session, user, symptom)


@router.post("/symptoms/batch", response_model=list[SymptomRead], status_code=status.HTTP_201_CREATED)
async def create_symptoms(body: SymptomBatch, user: CurrentUser, session: Session) -> list[dict]:
    """The Quick Log grid logs several symptoms at one moment."""
    tz = await resolve_timezone(session, user, body.tz)
    created = []
    for item in body.items:
        symptom = Symptom(
            user_id=user.id,
            notes=body.notes,
            duration_minutes=body.duration_minutes,
            **symptom_values(item.name, None, item.intensity, item.catalog_key, body.timestamp, tz),
        )
        session.add(symptom)
        created.append(symptom)

    await session.flush()
    await recompute_correlations(session, user.id)
    await session.commit()

    custom = await _custom_lookup(session, user)
    presented = []
    for symptom in created:
        await session.refresh(symptom)
        presented.append(
            {
                **{c.name: getattr(symptom, c.name) for c in Symptom.__table__.columns},
                **present_symptom(symptom, custom),
            }
        )
    return presented


@router.get("/symptom-catalog", response_model=SymptomCatalogRead)
async def read_catalog(user: CurrentUser, session: Session) -> dict:
    custom = await session.scalars(
        select(CustomSymptom).where(CustomSymptom.user_id == user.id).order_by(CustomSymptom.name)
    )
    return {
        "defaults": [
            CatalogItem(key=e.key, name=e.name, emoji=e.emoji, body_region=e.body_region)
            for e in SYMPTOM_CATALOG
        ],
        "custom": list(custom),
    }


@router.post("/symptom-catalog", response_model=CustomSymptomRead, status_code=status.HTTP_201_CREATED)
async def create_custom_symptom(
    body: CustomSymptomCreate, user: CurrentUser, session: Session
) -> CustomSymptom:
    key = custom_symptom_key(body.name)
    existing = await session.scalar(
        select(CustomSymptom).where(CustomSymptom.user_id == user.id, CustomSymptom.key == key)
    )
    row = existing or CustomSymptom(user_id=user.id, key=key)
    row.name = body.name
    row.emoji = body.emoji or "🩺"
    row.body_region = body.body_region
    session.add(row)
    await session.commit()
    await session.refresh(row)
    return row


@router.delete("/symptom-catalog/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_custom_symptom(item_id: int, user: CurrentUser, session: Session) -> None:
    row = await owned_or_404(session, CustomSymptom, item_id, user, "Symptom")
    await session.delete(row)
    await session.commit()


@router.put("/symptoms/{symptom_id}", response_model=SymptomRead)
async def update_symptom(
    symptom_id: int, body: SymptomPatch, user: CurrentUser, session: Session
) -> dict:
    symptom = await owned_or_404(session, Symptom, symptom_id, user, "Symptom")
    values = body.model_dump(exclude_unset=True)

    if body.notes is not None:
        symptom.notes = body.notes
    if "duration_minutes" in values:
        symptom.duration_minutes = body.duration_minutes
    if body.catalog_key is not None:
        symptom.catalog_key = body.catalog_key

    # Any change to the level or the time re-derives the stored pair and day.
    if body.name is not None or body.severity is not None or body.intensity is not None or body.timestamp is not None:
        tz = await resolve_timezone(session, user, body.tz)
        updated = symptom_values(
            body.name or symptom.name,
            body.severity if body.severity is not None else (None if body.intensity is not None else symptom.severity),
            body.intensity if body.intensity is not None else (None if body.severity is not None else symptom.intensity),
            body.catalog_key or symptom.catalog_key,
            body.timestamp or symptom.timestamp,
            tz,
        )
        for field, value in updated.items():
            setattr(symptom, field, value)

    session.add(symptom)
    await session.flush()
    await recompute_correlations(session, user.id)
    await session.commit()
    await session.refresh(symptom)
    return await _present(session, user, symptom)


@router.delete("/symptoms/{symptom_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_symptom(symptom_id: int, user: CurrentUser, session: Session) -> None:
    symptom = await owned_or_404(session, Symptom, symptom_id, user, "Symptom")
    await session.delete(symptom)
    await session.flush()
    await recompute_correlations(session, user.id)
    await session.commit()
