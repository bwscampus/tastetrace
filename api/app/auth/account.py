"""Self-service account routes that fastapi-users does not provide safely.

fastapi-users' `PATCH /users/me` changes email or password with nothing but
a session, so a stolen token is a full account takeover; its `DELETE` is
superuser-only, so users cannot leave. These two routes are mounted ahead of
fastapi-users' users router and shadow `PATCH /me`; `GET /me` and the
superuser `/{id}` routes still come from fastapi-users.

Production Standard: AUTH-5 (current password for sensitive changes, password
change ends other sessions) and AUTH-6 (self-service deletion; the App Store
requires it).
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from fastapi_users import exceptions
from fastapi_users.router.common import ErrorCode
from pydantic import BaseModel, Field
from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.models import AccessToken, User
from app.auth.router import current_active_user
from app.auth.schemas import UserRead, UserSelfUpdate, UserUpdate
from app.auth.users import UserManager, get_user_manager
from app.config import settings
from app.db import get_async_session

logger = logging.getLogger("app.auth")

router = APIRouter()


class AccountDelete(BaseModel):
    password: str = Field(min_length=1, max_length=1024)


def _presented_token(request: Request) -> str | None:
    """The session token this request authenticated with, cookie or bearer."""
    auth = request.headers.get("Authorization", "")
    if auth.lower().startswith("bearer "):
        return auth[7:].strip() or None
    return request.cookies.get(settings.SESSION_COOKIE_NAME)


def _password_matches(user_manager: UserManager, user: User, password: str | None) -> bool:
    if not password:
        return False
    verified, _ = user_manager.password_helper.verify_and_update(
        password, user.hashed_password
    )
    return verified


@router.patch("/me", response_model=UserRead, name="users:patch_current_user")
async def update_me(
    request: Request,
    body: UserSelfUpdate,
    user: User = Depends(current_active_user),
    user_manager: UserManager = Depends(get_user_manager),
    session: AsyncSession = Depends(get_async_session),
):
    changes_password = body.password is not None
    changes_email = body.email is not None and body.email.lower() != user.email.lower()

    if (changes_password or changes_email) and not _password_matches(
        user_manager, user, body.current_password
    ):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail={
                "code": ErrorCode.UPDATE_USER_INVALID_PASSWORD,
                "reason": "Current password is incorrect.",
            },
        )

    update = UserUpdate.model_validate(
        body.model_dump(exclude_unset=True, exclude={"current_password"})
    )
    try:
        updated = await user_manager.update(update, user, safe=True, request=request)
    except exceptions.InvalidPasswordException as e:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail={"code": ErrorCode.UPDATE_USER_INVALID_PASSWORD, "reason": e.reason},
        )
    except exceptions.UserAlreadyExists:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail=ErrorCode.UPDATE_USER_EMAIL_ALREADY_EXISTS,
        )

    if changes_password:
        # Keep the session that made the change; end every other one.
        current = _presented_token(request)
        await session.execute(
            delete(AccessToken).where(
                AccessToken.user_id == user.id, AccessToken.token != current
            )
        )
        await session.commit()
        logger.info("Revoked other sessions for %s after password change", user.id)

    return UserRead.model_validate(updated)


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT, name="users:delete_current_user")
async def delete_me(
    request: Request,
    body: AccountDelete,
    user: User = Depends(current_active_user),
    user_manager: UserManager = Depends(get_user_manager),
    session: AsyncSession = Depends(get_async_session),
) -> Response:
    if not _password_matches(user_manager, user, body.password):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail={"code": "DELETE_USER_INVALID_PASSWORD", "reason": "Password is incorrect."},
        )

    user_id = user.id
    await session.execute(delete(AccessToken).where(AccessToken.user_id == user_id))
    # Meals, symptoms, dishes, settings, etc. go with the user via ON DELETE CASCADE.
    await user_manager.delete(user, request=request)
    logger.info("Deleted account %s", user_id)

    response = Response(status_code=status.HTTP_204_NO_CONTENT)
    response.delete_cookie(
        settings.SESSION_COOKIE_NAME,
        httponly=True,
        secure=settings.cookie_secure,
        samesite="lax",
    )
    return response
