# TasteTrace API

The backend for the TasteTrace iOS app: accounts, the food and symptom log,
and the analytics behind the digests. Built from the `fastapi-backend` skill
template (fastapi-users, async SQLAlchemy, Alembic, Railway).

The Express app in `../app` is untouched and still serves the web client and
the landing page's waitlist. This service owns the mobile API only, with its
own database.

## Local development

```bash
uv sync
cp .env.example .env

docker run -d --name tt-pg-py -e POSTGRES_PASSWORD=test -p 55435:5432 postgres:18-alpine
# then set DATABASE_URL in .env to
#   postgresql+asyncpg://postgres:test@localhost:55435/postgres

uv run alembic upgrade head
uv run uvicorn app.main:app --reload --port 8000
uv run pytest
```

With the server running, the Swift client's end-to-end checker exercises every
endpoint the app uses:

```bash
cd ../ios/Packages/TasteTraceAPI && swift run apismoke http://localhost:8000
```

## Layout

```
app/
  auth/        fastapi-users: users, sessions, cookie + bearer transports
  domain/      pure logic — the analytics and the shared constants
  services/    everything that touches the database
  routers/     one module per resource
  models.py    project tables (auth tables live in auth/models.py)
  schemas.py   camelCase wire models
```

`app/domain` holds no I/O, so the rules that decide what the app shows are
testable on their own; `tests/test_domain_*.py` pins them to the numbers the
product was designed around.

## Conventions worth knowing

- **Auth.** The app signs in at `POST /api/auth/bearer/login` — form-encoded,
  following the OAuth2 password flow — and sends the token as
  `Authorization: Bearer`. Browsers can use the cookie routes instead; both
  mint the same revocable session rows, so a logout or password reset ends
  either. Passwords need 8 characters.
- **camelCase.** Responses are camelCase so the Swift models decode directly.
  Dictionary *keys* are data and are never renamed: the coverage slots
  (`Breakfast`), the timing windows (`0to4h`), the day-keyed markers.
- **Dates.** Timestamps are ISO-8601 UTC with exactly three fractional digits,
  which is what the client's decoder accepts. A `date` column holds the local
  calendar day an entry belongs to, derived server-side from the timestamp and
  the request's `tz`; the analytics bucket by it.
- **Ownership.** Every query filters on the user; someone else's row is a 404.
- **AI.** `ANTHROPIC_API_KEY` is optional. Without it — or on a timeout, error
  or refusal — the Food Suspect Digest summary is written from a template
  instead, and the endpoint still succeeds.

## Deploying

Railpack builds from `pyproject.toml` and `.python-version`; the `Procfile`
runs `alembic upgrade head` before the server starts, so migrations must stay
backward compatible with the running version. See the skill's
`references/railway.md`. Production refuses to boot without `SECRET_KEY`,
`RESEND_API_KEY`, real `ALLOWED_HOSTS` and an https `PUBLIC_BASE_URL`.
