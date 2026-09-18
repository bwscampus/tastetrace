"""Error bodies the iOS client can read.

FastAPI and fastapi-users return `{"detail": ...}`, where `detail` is
sometimes a string and sometimes a structure. The Swift client decodes
`{"message": String}`. Rather than teach one side about the other, every
error carries both keys: `detail` unchanged for anything reading the API
directly, and a flattened human-readable `message` for the app.
"""

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException


def flatten(detail: object) -> str:
    """A single readable sentence from any of FastAPI's detail shapes."""
    if isinstance(detail, str):
        return detail
    if isinstance(detail, dict):
        for key in ("reason", "message", "code"):
            value = detail.get(key)
            if isinstance(value, str):
                return value
        return "; ".join(f"{k}: {v}" for k, v in detail.items())
    if isinstance(detail, list):
        parts = []
        for item in detail:
            if isinstance(item, dict) and "loc" in item:
                field = ".".join(str(p) for p in item["loc"] if p != "body")
                parts.append(f"{field}: {item.get('msg', 'invalid')}" if field else str(item.get("msg", "invalid")))
            else:
                parts.append(flatten(item))
        return "; ".join(parts)
    return str(detail)


def install_error_shapes(app: FastAPI) -> None:
    @app.exception_handler(StarletteHTTPException)
    async def _http_error(request: Request, exc: StarletteHTTPException) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={"detail": exc.detail, "message": flatten(exc.detail)},
            headers=getattr(exc, "headers", None),
        )

    @app.exception_handler(RequestValidationError)
    async def _validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
        errors = exc.errors()
        return JSONResponse(
            status_code=422,
            content={
                "detail": jsonable(errors),
                "message": flatten(jsonable(errors)),
                "errors": jsonable(errors),
            },
        )


def jsonable(errors: list[dict]) -> list[dict]:
    """Validation errors can carry exception objects in `ctx`; drop them."""
    return [{k: v for k, v in error.items() if k != "ctx"} for error in errors]
