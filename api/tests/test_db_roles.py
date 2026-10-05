"""DB-6: the app's database role can read and write data but not change schema.

Runs against a real Postgres (roles don't exist in SQLite). Set
TEST_POSTGRES_URL to an owner/superuser URL on a scratch database, e.g.
    TEST_POSTGRES_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/app
CI provides one; locally the test is skipped without it.
"""

import os
import uuid

import pytest
from sqlalchemy import text
from sqlalchemy.engine import make_url
from sqlalchemy.exc import DBAPIError
from sqlalchemy.ext.asyncio import create_async_engine

from app.db_roles import LOGIN_ROLE, ensure_app_roles

OWNER_URL = os.environ.get("TEST_POSTGRES_URL")
pytestmark = pytest.mark.skipif(not OWNER_URL, reason="needs TEST_POSTGRES_URL (Postgres)")


def login_url(password: str) -> str:
    return (
        make_url(OWNER_URL)
        .set(username=LOGIN_ROLE, password=password)
        .render_as_string(hide_password=False)
    )


@pytest.fixture
async def owner():
    engine = create_async_engine(OWNER_URL)
    table = f"t_{uuid.uuid4().hex[:8]}"
    async with engine.begin() as conn:
        await conn.execute(text(f"CREATE TABLE {table} (id serial PRIMARY KEY, note text)"))
    yield engine, table
    async with engine.begin() as conn:
        await conn.execute(text(f"DROP TABLE IF EXISTS {table}, {table}_later"))
    await engine.dispose()


async def run_as_app(password: str, *statements: str):
    app = create_async_engine(login_url(password))
    try:
        async with app.begin() as conn:
            return [await conn.execute(text(s)) for s in statements]
    finally:
        await app.dispose()


async def test_app_role_can_do_crud_but_no_ddl(owner):
    engine, table = owner
    async with engine.begin() as conn:
        await ensure_app_roles(conn, "first-password-123")

    await run_as_app(
        "first-password-123",
        f"INSERT INTO {table} (note) VALUES ('hello')",
        f"UPDATE {table} SET note = 'updated'",
        f"SELECT * FROM {table}",
        f"DELETE FROM {table}",
    )

    for ddl in (
        "CREATE TABLE should_fail (id int)",
        f"DROP TABLE {table}",
        f"ALTER TABLE {table} ADD COLUMN x int",
        f"TRUNCATE {table}",
    ):
        with pytest.raises(DBAPIError):
            await run_as_app("first-password-123", ddl)


async def test_app_role_has_no_superpowers(owner):
    engine, _ = owner
    async with engine.begin() as conn:
        await ensure_app_roles(conn, "first-password-123")
    [row] = await run_as_app(
        "first-password-123",
        "SELECT rolsuper, rolbypassrls, rolcreatedb, rolcreaterole "
        "FROM pg_roles WHERE rolname = current_user",
    )
    assert tuple(row.one()) == (False, False, False, False)


async def test_tables_from_later_migrations_are_covered(owner):
    engine, table = owner
    async with engine.begin() as conn:
        await ensure_app_roles(conn, "first-password-123")
        # A migration that runs after the roles exist (same owner).
        await conn.execute(text(f"CREATE TABLE {table}_later (id serial PRIMARY KEY)"))
    await run_as_app("first-password-123", f"INSERT INTO {table}_later DEFAULT VALUES")


async def test_idempotent_and_rotates_password(owner):
    engine, table = owner
    async with engine.begin() as conn:
        await ensure_app_roles(conn, "first-password-123")
    async with engine.begin() as conn:
        await ensure_app_roles(conn, "second-password-456")  # rerun = rotate

    await run_as_app("second-password-456", f"SELECT * FROM {table}")
    # asyncpg raises its own InvalidPasswordError at connect time, unwrapped.
    with pytest.raises(Exception, match="password authentication failed"):
        await run_as_app("first-password-123", "SELECT 1")


async def test_password_with_quotes_is_safe(owner):
    engine, table = owner
    tricky = "it's'; DROP ROLE app_rw; --"
    async with engine.begin() as conn:
        await ensure_app_roles(conn, tricky)
    await run_as_app(tricky, f"SELECT * FROM {table}")
