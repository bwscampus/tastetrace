"""Profile and settings — the account screens of the iOS app."""

from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import func, select

from app.auth.models import User
from app.deps import CurrentUser, Session, get_settings_row, is_valid_timezone
from app.models import Meal, Symptom, UserSettings
from app.schemas import ProfilePatch, ProfileRead, SettingsPatch, SettingsRead

router = APIRouter(tags=["profile"])


async def _first_log_at(session, user: User) -> datetime | None:
    """The earliest meal or symptom, used for "journaler for N days"."""
    meal_at = await session.scalar(select(func.min(Meal.timestamp)).where(Meal.user_id == user.id))
    symptom_at = await session.scalar(
        select(func.min(Symptom.timestamp)).where(Symptom.user_id == user.id)
    )
    stamps = [t for t in (meal_at, symptom_at) if t is not None]
    return min(stamps) if stamps else None


def _aware(value: datetime | None) -> datetime | None:
    """SQLite hands back naive datetimes; treat them as UTC."""
    if value is not None and value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value


async def profile_payload(session, user: User) -> ProfileRead:
    first_log_at = _aware(await _first_log_at(session, user))
    since = first_log_at or _aware(user.created_at) or datetime.now(UTC)
    days = int((datetime.now(UTC) - since).total_seconds() // 86_400) + 1
    return ProfileRead(
        id=str(user.id),
        email=user.email,
        first_name=user.first_name,
        last_name=user.last_name,
        display_name=user.display_name,
        avatar_emoji=user.avatar_emoji,
        discovery_purpose=user.discovery_purpose,
        sensitivity_tags=user.sensitivity_tags or [],
        created_at=_aware(user.created_at),
        journaler_days=max(1, days),
        first_log_at=first_log_at,
    )


@router.get("/profile", response_model=ProfileRead)
async def read_profile(user: CurrentUser, session: Session) -> ProfileRead:
    return await profile_payload(session, user)


@router.patch("/profile", response_model=ProfileRead)
async def update_profile(patch: ProfilePatch, user: CurrentUser, session: Session) -> ProfileRead:
    for field, value in patch.model_dump(exclude_unset=True).items():
        setattr(user, field, value)
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return await profile_payload(session, user)


@router.get("/settings", response_model=SettingsRead)
async def read_settings(user: CurrentUser, session: Session) -> UserSettings:
    row = await get_settings_row(session, user)
    await session.commit()
    return row


@router.patch("/settings", response_model=SettingsRead)
async def update_settings(patch: SettingsPatch, user: CurrentUser, session: Session) -> UserSettings:
    values = patch.model_dump(exclude_unset=True)
    if "timezone" in values and not is_valid_timezone(values["timezone"]):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Unknown timezone")

    row = await get_settings_row(session, user)
    for field, value in values.items():
        setattr(row, field, value)
    row.updated_at = datetime.now(UTC)
    session.add(row)
    await session.commit()
    await session.refresh(row)

    # Thresholds feed every association, so they have to be recomputed.
    if {"correlation_window_hours", "min_trigger_count"} & values.keys():
        from app.services.correlations import recompute_correlations

        await recompute_correlations(session, row.user_id)
        await session.commit()
    return row
