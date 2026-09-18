"""Test fixtures.

Environment is set before app modules import, because Settings and the
SQLAlchemy engine are both module-level singletons.
"""

import os

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("SECRET_KEY", "test-secret-key-that-is-long-enough-xxxx")
os.environ.setdefault("DATABASE_URL", "sqlite+aiosqlite:///:memory:")
os.environ.setdefault("PUBLIC_BASE_URL", "http://testserver")
os.environ.pop("RESEND_API_KEY", None)

import pytest  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402
from sqlalchemy.ext.asyncio import (  # noqa: E402
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.pool import StaticPool  # noqa: E402

from app.db import Base, get_async_session  # noqa: E402
from app.main import create_app  # noqa: E402


@pytest.fixture
async def engine():
    # StaticPool keeps one connection, so an in-memory database survives
    # across sessions within a test.
    test_engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield test_engine
    await test_engine.dispose()


@pytest.fixture
async def client(engine):
    app = create_app()
    session_maker = async_sessionmaker(engine, expire_on_commit=False)

    async def override_get_async_session():
        async with session_maker() as session:
            yield session

    app.dependency_overrides[get_async_session] = override_get_async_session

    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://testserver"
    ) as ac:
        yield ac


@pytest.fixture
def credentials():
    return {"email": "athlete@example.com", "password": "correct horse battery"}


@pytest.fixture
async def registered(client, credentials):
    response = await client.post("/api/auth/register", json=credentials)
    assert response.status_code == 201, response.text
    return response.json()
