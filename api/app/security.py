"""Security middleware: response headers, CORS, and trusted hosts."""

from collections.abc import Awaitable, Callable

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.middleware.trustedhost import TrustedHostMiddleware

from app.config import Settings

HSTS = "max-age=31536000; includeSubDomains"


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Headers that cost nothing and close off whole bug classes.

    CSP is the one that needs per-project tuning — see Settings.
    """

    def __init__(self, app, settings: Settings) -> None:
        super().__init__(app)
        self._settings = settings
        self._csp = settings.content_security_policy()

    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        response = await call_next(request)
        headers = response.headers
        headers.setdefault("Content-Security-Policy", self._csp)
        headers.setdefault("X-Content-Type-Options", "nosniff")
        headers.setdefault("X-Frame-Options", "DENY")
        headers.setdefault(
            "Referrer-Policy", "strict-origin-when-cross-origin"
        )
        headers.setdefault(
            "Permissions-Policy",
            "geolocation=(), microphone=(), camera=(), payment=()",
        )
        headers.setdefault("Cross-Origin-Opener-Policy", "same-origin")
        if self._settings.is_production:
            headers.setdefault("Strict-Transport-Security", HSTS)
        return response


def install_security_middleware(app: FastAPI, settings: Settings) -> None:
    """Attach security middleware.

    Starlette runs middleware in reverse order of registration, so the calls
    below execute outermost-last: TrustedHost sees the request first, then
    CORS, then the header layer on the way back out.
    """
    app.add_middleware(SecurityHeadersMiddleware, settings=settings)

    if settings.ALLOWED_ORIGINS:
        # Credentials + an explicit allowlist. Never "*" with credentials —
        # browsers reject it, and it would be wrong if they didn't.
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.ALLOWED_ORIGINS,
            allow_credentials=True,
            allow_methods=["GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"],
            allow_headers=["Authorization", "Content-Type"],
            max_age=600,
        )

    if settings.ALLOWED_HOSTS and settings.ALLOWED_HOSTS != ["*"]:
        app.add_middleware(
            TrustedHostMiddleware, allowed_hosts=settings.ALLOWED_HOSTS
        )
