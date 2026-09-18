"""Application factory.

Order matters in two places and both are easy to get wrong:

1. Middleware. Starlette wraps each `add_middleware` call around the previous
   one, so the LAST registered runs FIRST. Registration below is therefore
   written inside-out.
2. Routes vs. static files. The catch-all StaticFiles mount at "/" must be
   added after every API router, or it swallows them and every /api call
   returns 404.
"""

import logging
from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from app.auth.router import install_auth_routes
from app.config import Settings, settings
from app.logging import (
    RequestContextMiddleware,
    configure_logging,
    install_exception_handlers,
)
from app.rate_limit import RateLimitMiddleware
from app.routers import health
from app.security import install_security_middleware

logger = logging.getLogger("app")

PUBLIC_DIR = Path(__file__).resolve().parent.parent / "public"


def create_app(config: Settings | None = None) -> FastAPI:
    config = config or settings
    configure_logging()

    app = FastAPI(
        title=config.APP_NAME,
        version=config.VERSION,
        # An attacker reading your schema is a gift. Keep docs to non-prod.
        docs_url=None if config.is_production else "/docs",
        redoc_url=None if config.is_production else "/redoc",
        openapi_url=None if config.is_production else "/openapi.json",
    )

    install_exception_handlers(app)

    # Registered inside-out: RequestContext ends up outermost so every log
    # line, including the security layer's, carries a request id.
    install_security_middleware(app, config)
    app.add_middleware(RateLimitMiddleware, settings=config)
    app.add_middleware(RequestContextMiddleware)

    app.include_router(health.router, prefix="/api", tags=["health"])
    install_auth_routes(app, prefix="/api")

    register_project_routes(app)

    # Must stay last. html=True serves index.html at "/".
    if PUBLIC_DIR.is_dir():
        app.mount(
            "/", StaticFiles(directory=PUBLIC_DIR, html=True), name="static"
        )
    else:
        logger.warning("No public/ directory at %s — serving API only", PUBLIC_DIR)

    return app


def register_project_routes(app: FastAPI) -> None:
    """Hook for project-specific routers.

    Keeping project routes behind one function is what lets a project pull
    template updates without a merge conflict in create_app().
    """
    from app.routers import (
        ai,
        analytics,
        dishes,
        entries,
        export,
        meals,
        profile,
        symptoms,
        watchlist,
    )
    from app.routers.errors import install_error_shapes

    install_error_shapes(app)
    for module in (profile, meals, dishes, symptoms, entries, analytics, watchlist, ai, export):
        app.include_router(module.router, prefix="/api")


app = create_app()
