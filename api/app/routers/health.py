"""Health endpoint. Railway's healthcheckPath points here.

It pings the database so a deploy with a dead or unreachable Postgres fails
its health check instead of serving 500s, and it says nothing about the
environment or version (API-9).
"""

import logging

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_async_session

logger = logging.getLogger("app.health")

router = APIRouter()


@router.get("/health")
async def health(session: AsyncSession = Depends(get_async_session)):
    try:
        await session.execute(text("SELECT 1"))
    except Exception:
        logger.exception("Health check: database unreachable")
        return JSONResponse(status_code=503, content={"status": "unavailable"})
    return {"status": "ok"}
