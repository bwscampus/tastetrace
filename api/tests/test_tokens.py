"""DB-8: access_tokens stores SHA-256 hashes, never the bearer value."""

import os

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.auth.models import AccessToken
from app.auth.tokens import hash_token
from app.config import settings
from tests.conftest_project import PASSWORD, register_and_login


async def stored_tokens(engine) -> list[str]:
    async with async_sessionmaker(engine)() as session:
        return list(await session.scalars(select(AccessToken.token)))


def test_hash_token_shape():
    hashed = hash_token("abc")
    assert len(hashed) == 43, "must fit the existing access_tokens.token column"
    assert hashed == "ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0"
    assert hash_token("abc") == hashed, "deterministic"


async def test_cookie_login_stores_only_the_hash(client, engine):
    await client.post(
        "/api/auth/register", json={"email": "cookie@example.com", "password": PASSWORD}
    )
    response = await client.post(
        "/api/auth/login", data={"username": "cookie@example.com", "password": PASSWORD}
    )
    assert response.status_code == 204, response.text
    raw = response.cookies[settings.SESSION_COOKIE_NAME]

    assert await stored_tokens(engine) == [hash_token(raw)]
    assert raw not in await stored_tokens(engine)
    assert (await client.get("/api/users/me")).status_code == 200


async def test_bearer_login_stores_only_the_hash_and_still_works(client, engine):
    auth = await register_and_login(client, "ios-hash@example.com")
    raw = auth["Authorization"].removeprefix("Bearer ")

    stored = await stored_tokens(engine)
    assert hash_token(raw) in stored
    assert raw not in stored
    assert (await client.get("/api/users/me", headers=auth)).status_code == 200


async def test_stored_hash_is_not_a_usable_token(client, engine):
    await register_and_login(client, "leak@example.com")
    [leaked] = await stored_tokens(engine)
    response = await client.get(
        "/api/users/me", headers={"Authorization": f"Bearer {leaked}"}
    )
    assert response.status_code == 401, "a value read from the database must not work as a session"


async def test_logout_deletes_the_hashed_row(client, engine):
    auth = await register_and_login(client, "bye@example.com")
    assert len(await stored_tokens(engine)) == 1
    response = await client.post("/api/auth/bearer/logout", headers=auth)
    assert response.status_code in (200, 204), response.text
    assert await stored_tokens(engine) == []
    assert (await client.get("/api/users/me", headers=auth)).status_code == 401


@pytest.mark.skipif(
    not os.environ.get("TEST_POSTGRES_URL"), reason="needs TEST_POSTGRES_URL (Postgres)"
)
async def test_migration_sql_matches_python_hash():
    """Migration 0004 must hash existing rows exactly like hash_token()."""
    import importlib.util
    from pathlib import Path

    from sqlalchemy import text
    from sqlalchemy.ext.asyncio import create_async_engine

    path = Path(__file__).parent.parent / "migrations/versions/0004_hash_access_tokens.py"
    spec = importlib.util.spec_from_file_location("m0004", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    samples = ["abc", "tt_ZXhhbXBsZQ", "Vq1x9-_aZ3kLmN0pQrStUvWxYz0123456789AbCdEfG"]
    pg = create_async_engine(os.environ["TEST_POSTGRES_URL"])
    try:
        async with pg.connect() as conn:
            for raw in samples:
                sql_hash = await conn.scalar(
                    text(f"SELECT {module.HASH_SQL.format(col='CAST(:t AS text)')}"),
                    {"t": raw},
                )
                assert sql_hash == hash_token(raw), raw
    finally:
        await pg.dispose()
