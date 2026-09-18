"""Authentication backend: httpOnly cookie + database-backed sessions.

Why not a JWT bearer token: a JWT has to live somewhere JavaScript can read
it, so any XSS exfiltrates a portable credential, and nothing can revoke it
before it expires. An opaque cookie is unreadable to JS, and a session row can
be deleted the instant a user logs out or resets their password.

The tradeoff is CSRF, since browsers attach cookies automatically. SameSite=Lax
blocks the cross-site form-POST case; add a CSRF token if you ever need
SameSite=None.
"""

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


def get_database_strategy(
    access_token_db: AccessTokenDatabase[AccessToken] = Depends(
        get_access_token_db
    ),
) -> DatabaseStrategy:
    return DatabaseStrategy(
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
