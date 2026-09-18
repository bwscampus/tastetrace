"""Async SQLAlchemy engine, session dependency, and declarative base."""

from collections.abc import AsyncGenerator

from sqlalchemy import JSON, event
from sqlalchemy.dialects import postgresql
from sqlalchemy.engine import Engine
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from app.config import settings

# JSONB in Postgres, plain JSON on SQLite so the test suite needs no server.
JSONDocument = JSON().with_variant(postgresql.JSONB, "postgresql")


class Base(DeclarativeBase):
    pass


engine = create_async_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True,  # survives Postgres dropping idle connections
    echo=False,
)

async_session_maker = async_sessionmaker(engine, expire_on_commit=False)


@event.listens_for(Engine, "connect")
def _enforce_sqlite_foreign_keys(dbapi_connection, _record) -> None:
    """SQLite ignores foreign keys unless asked; Postgres never does.

    Without this the test database would skip ON DELETE SET NULL and ON DELETE
    CASCADE, so the suite would pass on behaviour production doesn't have.
    The connection is an aiosqlite adapter, not a raw sqlite3 one, so match on
    the dialect module rather than the driver.
    """
    if "sqlite" not in type(dbapi_connection).__module__:
        return
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()


async def get_async_session() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_maker() as session:
        yield session
