# app

FastAPI backend: email/password accounts, cookie sessions, password reset,
Postgres, and a Railway deploy that migrates on release. Optionally serves a
static frontend from `public/`.

## Local development

```bash
uv sync
cp .env.example .env

# Postgres in a container (any local Postgres works too)
docker run -d --name app-pg \
  -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=app \
  -p 5432:5432 postgres:17-alpine

uv run alembic upgrade head
uv run uvicorn app.main:app --reload
```

- App: http://localhost:8000
- API docs: http://localhost:8000/docs (disabled in production)
- Health: http://localhost:8000/api/health

## Tests

```bash
uv run pytest
```

They run on in-memory SQLite, so no database server is needed. They assert the
security properties — an XSS-proof session cookie, revocation on password
reset, no account enumeration, working rate limits — so a failure means a
property is gone, not that a test is stale.

## Layout

```
app/
  main.py       app factory; middleware order; register_project_routes()
  config.py     settings, validated at import
  db.py         async engine + session dependency
  security.py   CSP and security headers, CORS, TrustedHost
  logging.py    request ids, generic 500s
  rate_limit.py per-IP limits on auth routes
  auth/         users, sessions, password reset
  email/        Resend client + templates
  routers/      health, plus your routes
  models.py     your tables (create this)
public/         static frontend, mounted at / when present
migrations/     alembic
Procfile        start command (migrate, then serve)
```

## Adding to it

Put new routers inside `register_project_routes()` in `app/main.py` and new
tables in `app/models.py`, then
`uv run alembic revision --autogenerate -m "..."`. Keeping project code out of
`create_app()` and out of `app/auth/` is what makes template updates painless.

## Deploying

See `references/railway.md` in the skill. Short version: `railway init`,
`railway add --database postgres`, `railway add --service <name>`,
`railway domain`, set `SECRET_KEY` / `RESEND_API_KEY` / `EMAIL_FROM` /
`PUBLIC_BASE_URL` / `ALLOWED_HOSTS` / `ENVIRONMENT=production` and
`DATABASE_URL=${{Postgres.DATABASE_URL}}`, then `railway up`.

The start command lives in `Procfile`.

The app refuses to start in production with placeholder or missing secrets.
That's intentional: a failed deploy leaves the previous version serving.
