"""API-facing user shapes. Kept separate from the ORM model on purpose.

Serialised camelCase like every other response, so the iOS client decodes one
convention throughout (`isActive`, `displayName`). Requests may still send
snake_case, since `populate_by_name` accepts both.
"""

import uuid
from datetime import datetime

from fastapi_users import schemas
from pydantic import ConfigDict, Field
from pydantic.alias_generators import to_camel

_camel = ConfigDict(alias_generator=to_camel, populate_by_name=True, from_attributes=True)


class UserRead(schemas.BaseUser[uuid.UUID]):
    model_config = _camel

    first_name: str | None = None
    last_name: str | None = None
    display_name: str | None = None
    avatar_emoji: str | None = None
    discovery_purpose: str | None = None
    sensitivity_tags: list[str] = Field(default_factory=list)
    created_at: datetime | None = None


class UserCreate(schemas.BaseUserCreate):
    model_config = _camel

    first_name: str | None = None
    last_name: str | None = None
    display_name: str | None = None


class UserUpdate(schemas.BaseUserUpdate):
    """What a user may change about themselves.

    `is_superuser` / `is_verified` are inherited but ignored for non-superusers
    by fastapi-users, and `hashed_password` is never exposed.
    """

    model_config = _camel

    first_name: str | None = None
    last_name: str | None = None
    display_name: str | None = None
    avatar_emoji: str | None = None
    discovery_purpose: str | None = None
    sensitivity_tags: list[str] | None = None
