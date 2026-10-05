"""Create/refresh the least-privilege database role the app runs as.

    python -m app.db_roles        # runs after `alembic upgrade head` on deploy

Two roles:

- ``app_rw``: NOLOGIN group. SELECT/INSERT/UPDATE/DELETE on every table and
  USAGE/SELECT on every sequence in ``public``, plus default privileges so
  tables added by future migrations are covered automatically. No DDL, not a
  superuser, no BYPASSRLS, and no access to ``alembic_version``.
- ``app_rw_login``: LOGIN member of ``app_rw``. Created, and its password
  (re)set, only when APP_DB_PASSWORD is set, so dev and tests skip it and
  changing the variable rotates the password on the next deploy.

Runs with the owner credentials (MIGRATION_DATABASE_URL, else DATABASE_URL).
Every statement is idempotent. The password goes in as a bind parameter and
is quoted by Postgres's format('%L'); it is never logged.

Production Standard: DB-6.
"""

import asyncio
import logging

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection, create_async_engine

from app.config import settings

logger = logging.getLogger("app.db_roles")

GROUP_ROLE = "app_rw"
LOGIN_ROLE = "app_rw_login"

_GROUP_SQL = [
    f"""
    DO $$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '{GROUP_ROLE}') THEN
        CREATE ROLE {GROUP_ROLE} NOLOGIN;
      END IF;
    END $$
    """,
    f"ALTER ROLE {GROUP_ROLE} NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS",
    f"""
    DO $$ BEGIN
      EXECUTE format('GRANT CONNECT ON DATABASE %I TO {GROUP_ROLE}', current_database());
    END $$
    """,
    # Postgres < 15 lets every role create tables in public; nobody but the
    # owner should.
    "REVOKE CREATE ON SCHEMA public FROM PUBLIC",
    f"GRANT USAGE ON SCHEMA public TO {GROUP_ROLE}",
    f"GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO {GROUP_ROLE}",
    f"GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO {GROUP_ROLE}",
    f"ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO {GROUP_ROLE}",
    f"ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO {GROUP_ROLE}",
    # The app has no business rewriting migration history.
    f"""
    DO $$ BEGIN
      IF to_regclass('public.alembic_version') IS NOT NULL THEN
        REVOKE ALL ON public.alembic_version FROM {GROUP_ROLE};
      END IF;
    END $$
    """,
]

_LOGIN_SQL = [
    f"""
    DO $$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '{LOGIN_ROLE}') THEN
        CREATE ROLE {LOGIN_ROLE} LOGIN;
      END IF;
    END $$
    """,
    f"GRANT {GROUP_ROLE} TO {LOGIN_ROLE}",
]


async def ensure_app_roles(conn: AsyncConnection, password: str | None) -> None:
    for statement in _GROUP_SQL:
        await conn.execute(text(statement))
    if not password:
        logger.info("APP_DB_PASSWORD unset; skipped %s", LOGIN_ROLE)
        return
    for statement in _LOGIN_SQL:
        await conn.execute(text(statement))
    alter = await conn.scalar(
        text(
            "SELECT format('ALTER ROLE "
            + LOGIN_ROLE
            + " WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS"
            " INHERIT PASSWORD %L', CAST(:pw AS text))"
        ),
        {"pw": password},
    )
    await conn.execute(text(alter))


async def main() -> None:
    url = settings.migration_database_url
    if not url.startswith("postgresql"):
        logger.info("Not Postgres (%s); nothing to do", url.split(":", 1)[0])
        return
    engine = create_async_engine(url)
    try:
        async with engine.begin() as conn:
            await ensure_app_roles(conn, settings.APP_DB_PASSWORD)
    finally:
        await engine.dispose()
    logger.info("Database roles up to date (%s, %s)", GROUP_ROLE, LOGIN_ROLE)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
    asyncio.run(main())
