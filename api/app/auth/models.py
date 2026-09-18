"""Auth tables.

`users` and `access_tokens` come from fastapi-users' SQLAlchemy adapter. A
project's own tables live elsewhere (see references/schema.md) so template
migrations and project migrations never fight over the same revisions.

The project columns on `User` are the profile fields the iOS app edits; they
are additive, so a future template update to this file is a small merge.
"""

from datetime import UTC, datetime

from fastapi_users_db_sqlalchemy import SQLAlchemyBaseUserTableUUID
from fastapi_users_db_sqlalchemy.access_token import (
    SQLAlchemyBaseAccessTokenTableUUID,
)
from fastapi_users_db_sqlalchemy.generics import GUID
from sqlalchemy import DateTime, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, declared_attr, mapped_column

from app.db import Base, JSONDocument


class User(SQLAlchemyBaseUserTableUUID, Base):
    """id, email, hashed_password, is_active, is_superuser, is_verified.

    Add project columns here, then generate a migration.
    """

    __tablename__ = "users"

    first_name: Mapped[str | None] = mapped_column(String(60), nullable=True)
    last_name: Mapped[str | None] = mapped_column(String(60), nullable=True)
    display_name: Mapped[str | None] = mapped_column(String(80), nullable=True)
    avatar_emoji: Mapped[str | None] = mapped_column(String(16), nullable=True)
    discovery_purpose: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Self-reported sensitivities ("gluten", "dairy"): a short, client-owned list
    sensitivity_tags: Mapped[list[str]] = mapped_column(
        JSONDocument, nullable=False, default=list
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=lambda: datetime.now(UTC)
    )


class AccessToken(SQLAlchemyBaseAccessTokenTableUUID, Base):
    """Server-side sessions.

    A row per logged-in device. Deleting rows logs that device out
    immediately — the whole reason we don't use stateless JWTs.
    """

    __tablename__ = "access_tokens"

    @declared_attr
    def user_id(cls) -> Mapped[GUID]:
        # The base class points at "user.id"; we use the plural table name,
        # so the foreign key has to be redeclared here.
        return mapped_column(
            GUID, ForeignKey("users.id", ondelete="cascade"), nullable=False
        )
