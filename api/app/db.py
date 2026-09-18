"""Async SQLAlchemy engine, session dependency, and declarative base."""

from collections.abc import AsyncGenerator

from sqlalchemy import JSON
from sqlalchemy.dialects import postgresql
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


async def get_async_session() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_maker() as session:
        yield session
