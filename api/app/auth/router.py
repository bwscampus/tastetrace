"""Wires fastapi-users' routers onto the app."""

import uuid

from fastapi import APIRouter, FastAPI
from fastapi_users import FastAPIUsers

from app.auth.backend import bearer_backend, cookie_backend
from app.auth.models import User
from app.auth.schemas import UserCreate, UserRead, UserUpdate
from app.auth.users import get_user_manager
from app.config import settings

# Both backends share one session table, so a token from either is revocable.
fastapi_users = FastAPIUsers[User, uuid.UUID](
    get_user_manager, [cookie_backend, bearer_backend]
)

# Use as a dependency to require a logged-in user on your own routes:
#     user: User = Depends(current_active_user)
current_active_user = fastapi_users.current_user(active=True)
current_optional_user = fastapi_users.current_user(active=True, optional=True)


def install_auth_routes(app: FastAPI, prefix: str = "/api") -> None:
    auth_router = APIRouter()
    # POST /login, POST /logout  (browsers; the template's contract tests
    # cover these paths, so they stay where the template put them)
    auth_router.include_router(fastapi_users.get_auth_router(cookie_backend))
    # POST /bearer/login, POST /bearer/logout  (the iOS app)
    auth_router.include_router(
        fastapi_users.get_auth_router(bearer_backend), prefix="/bearer"
    )
    # POST /register
    auth_router.include_router(
        fastapi_users.get_register_router(UserRead, UserCreate)
    )
    # POST /forgot-password, POST /reset-password. Mounted only when mail is
    # configured: a reset route that cannot deliver is worse than no route,
    # because it answers 202 and the user waits for an email that never comes.
    if settings.PASSWORD_RESET_ENABLED:
        auth_router.include_router(fastapi_users.get_reset_password_router())

    app.include_router(auth_router, prefix=f"{prefix}/auth", tags=["auth"])
    # GET/PATCH /me
    app.include_router(
        fastapi_users.get_users_router(UserRead, UserUpdate),
        prefix=f"{prefix}/users",
        tags=["users"],
    )
