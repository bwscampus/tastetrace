"""UserManager: the hooks fastapi-users calls around auth events."""

import logging
import uuid
from collections.abc import AsyncGenerator
from typing import Optional, Union

from fastapi import Depends, Request
from fastapi_users import BaseUserManager, InvalidPasswordException, UUIDIDMixin
from fastapi_users_db_sqlalchemy import SQLAlchemyUserDatabase
from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.models import AccessToken, User
from app.auth.schemas import UserCreate
from app.config import settings
from app.db import get_async_session
from app.email.resend_client import EmailNotConfigured, send_email
from app.email.templates import reset_password_email

logger = logging.getLogger("app.auth")


class UserManager(UUIDIDMixin, BaseUserManager[User, uuid.UUID]):
    reset_password_token_secret = settings.SECRET_KEY
    verification_token_secret = settings.SECRET_KEY
    reset_password_token_lifetime_seconds = (
        settings.RESET_TOKEN_LIFETIME_SECONDS
    )

    MIN_PASSWORD_LENGTH = 8

    async def validate_password(
        self, password: str, user: Union[UserCreate, User]
    ) -> None:
        """Minimum viable policy: length, and not the email address.

        Deliberately not a maze of character-class rules — those push people
        toward Passw0rd! and away from long passphrases. Length is what
        actually costs an attacker time.
        """
        if len(password) < self.MIN_PASSWORD_LENGTH:
            raise InvalidPasswordException(
                reason=(
                    f"Password must be at least {self.MIN_PASSWORD_LENGTH} "
                    "characters."
                )
            )
        email = getattr(user, "email", "") or ""
        if email and email.lower() in password.lower():
            raise InvalidPasswordException(
                reason="Password must not contain your email address."
            )

    async def on_after_register(
        self, user: User, request: Optional[Request] = None
    ) -> None:
        logger.info("Registered user %s", user.id)

    async def on_after_forgot_password(
        self, user: User, token: str, request: Optional[Request] = None
    ) -> None:
        subject, html = reset_password_email(token)
        try:
            await send_email(user.email, subject, html)
        except EmailNotConfigured:
            logger.error(
                "Password reset requested for %s but email is not configured",
                user.id,
            )
        except Exception:
            # Any delivery failure — bad API key, unverified domain, Resend
            # outage — must be swallowed here. Letting it propagate would turn
            # /forgot-password into a 500 for real accounts and a 202 for
            # unknown ones, which hands out exactly the account-enumeration
            # oracle the endpoint is written to avoid.
            logger.exception("Failed to send password reset for %s", user.id)

    async def on_after_reset_password(
        self, user: User, request: Optional[Request] = None
    ) -> None:
        """Sign every device out after a password change.

        Someone resetting their password may be doing it because another
        person has access. Leaving existing sessions alive would defeat the
        point. This is the concrete payoff of database-backed sessions —
        a stateless JWT could not be revoked here.
        """
        session: AsyncSession | None = getattr(self.user_db, "session", None)
        if session is None:  # pragma: no cover - adapter always sets this
            logger.warning("Could not revoke sessions for %s", user.id)
            return
        await session.execute(
            delete(AccessToken).where(AccessToken.user_id == user.id)
        )
        await session.commit()
        logger.info("Revoked all sessions for %s after password reset", user.id)


async def get_user_db(
    session: AsyncSession = Depends(get_async_session),
) -> AsyncGenerator[SQLAlchemyUserDatabase, None]:
    yield SQLAlchemyUserDatabase(session, User)


async def get_user_manager(
    user_db: SQLAlchemyUserDatabase = Depends(get_user_db),
) -> AsyncGenerator[UserManager, None]:
    yield UserManager(user_db)
