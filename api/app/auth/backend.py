"""Authentication backend: httpOnly cookie + database-backed sessions.

Why not a JWT bearer token: a JWT has to live somewhere JavaScript can read
it, so any XSS exfiltrates a portable credential, and nothing can revoke it
before it expires. An opaque cookie is unreadable to JS, and a session row can
be deleted the instant a user logs out or resets their password.

The tradeoff is CSRF, since browsers attach cookies automatically. SameSite=Lax
blocks the cross-site form-POST case; add a CSRF token if you ever need
SameSite=None.
"""

import secrets
from collections.abc import AsyncGenerator

from fastapi import Depends
from fastapi_users.authentication import (
    AuthenticationBackend,
    BearerTransport,
    CookieTransport,
)
from fastapi_users.authentication.strategy.db import (
    AccessTokenDatabase,
    DatabaseStrategy,
)
from fastapi_users_db_sqlalchemy.access_token import (
    SQLAlchemyAccessTokenDatabase,
)
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.models import AccessToken
from app.auth.tokens import hash_token
from app.config import settings
from app.db import get_async_session

# The iOS app carries the token in an Authorization header and keeps it in the
# keychain: a native app has no cookie jar worth relying on, and no XSS surface
# for a readable token. Both transports mint and validate the SAME database
# sessions (access_tokens), so logout and password reset revoke either one.
bearer_transport = BearerTransport(tokenUrl="api/auth/bearer/login")

cookie_transport = CookieTransport(
    cookie_name=settings.SESSION_COOKIE_NAME,
    cookie_max_age=settings.SESSION_LIFETIME_SECONDS,
    cookie_httponly=True,
    cookie_secure=settings.cookie_secure,  # False on localhost, True in prod
    cookie_samesite="lax",
)


async def get_access_token_db(
    session: AsyncSession = Depends(get_async_session),
) -> AsyncGenerator[SQLAlchemyAccessTokenDatabase[AccessToken], None]:
    yield SQLAlchemyAccessTokenDatabase(session, AccessToken)


class HashedDatabaseStrategy(DatabaseStrategy):
    """DatabaseStrategy that stores SHA-256(token) instead of the token.

    The raw value goes to the client once, at login; every later lookup
    hashes what the client presents. See app/auth/tokens.py.
    """

    async def read_token(self, token, user_manager):
        if token is None:
            return None
        return await super().read_token(hash_token(token), user_manager)

    async def write_token(self, user) -> str:
        raw = secrets.token_urlsafe()
        await self.database.create({"token": hash_token(raw), "user_id": user.id})
        return raw

    async def destroy_token(self, token: str, user) -> None:
        await super().destroy_token(hash_token(token), user)


def get_database_strategy(
    access_token_db: AccessTokenDatabase[AccessToken] = Depends(
        get_access_token_db
    ),
) -> DatabaseStrategy:
    return HashedDatabaseStrategy(
        access_token_db, lifetime_seconds=settings.SESSION_LIFETIME_SECONDS
    )


cookie_backend = AuthenticationBackend(
    name="cookie",
    transport=cookie_transport,
    get_strategy=get_database_strategy,
)

bearer_backend = AuthenticationBackend(
    name="bearer",
    transport=bearer_transport,
    get_strategy=get_database_strategy,
)

# Kept as the default name for template compatibility.
auth_backend = cookie_backend
