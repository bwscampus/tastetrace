# tastetrace

Three services in one Railway project, plus the iOS client. Each service
builds from its own root directory and redeploys on pushes to `main`.

| Folder | What it is | Railway service | Domain |
| --- | --- | --- | --- |
| `landing/` | Static waitlist landing page (`index.html`, no build step) | `landing` | https://tastetrace.up.railway.app (later tastetrace.app) |
| `app/` | The TasteTrace web application: React (Vite) client + Express API + Postgres (Drizzle) | `tastetrace` | https://tastetrace-app.up.railway.app (later app.tastetrace.app) |
| `api/` | The mobile API: FastAPI + Postgres (SQLAlchemy/Alembic), its own database | `tastetrace-api` | https://tastetrace-api-production.up.railway.app |
| `ios/` | Native SwiftUI app; open `ios/TasteTrace.xcworkspace` | — | — |

The sites run on their Railway domains for now. The custom domains are already
attached to the services in Railway and start working once their DNS records
are added; at that point change `WAITLIST_URL` in `landing/index.html` to
`https://app.tastetrace.app/api/waitlist`.

The landing page's waitlist form posts to the app's `/api/waitlist`, which
stores signups in the `waitlist_signups` table.

## app/

```sh
cd app
npm install
npm run dev        # http://localhost:5000 (set PORT to change)
npm run db:push    # apply shared/schema.ts to the database
npm run check      # type-check
npm test           # unit tests; the API integration tests also run when DATABASE_URL points at a scratch Postgres
```

Environment variables:

- `DATABASE_URL` – Postgres connection string the app runs as (on Railway: `${{Postgres.DATABASE_URL}}`,
  or the restricted `app_rw_login` after the cut-over in "Database roles")
- `MIGRATION_DATABASE_URL` – optional owner connection string for `db:push` and `db:roles`
- `APP_DB_PASSWORD` – optional; when set, `db:roles` creates/re-passwords `app_rw_login`
- `SESSION_SECRET` – secret for signing session cookies
- `WAITLIST_ORIGINS` – optional, comma-separated origins allowed to post to
  `/api/waitlist` (defaults to the landing page's Railway and tastetrace.app origins)
- `ANTHROPIC_API_KEY` – optional; enables the Claude-written "AI Pattern
  Synthesis" in the Food Suspect Digest. Without it a rule-based summary is used.

Railway builds with `npm run build` and runs `npm start`: a single Node server
that serves the API and the built client on `PORT`. `npm run db:push` runs as
a pre-deploy step, so schema changes in `shared/schema.ts` must stay additive.

This Express API serves the web client only. The iOS app talks to the FastAPI
service in `api/`, which has its own database, so the same email on the web and
in the app is two unrelated accounts. See `docs/ios-build-plan.md` for the
mobile API and the iOS app plan.

## Database roles (least privilege)

> **Status: code ready on `security/db-hardening`; not yet applied in production.**
> Until the cut-over below, both apps still connect as the `postgres` superuser.

Each deploy runs a role step after migrations: `python -m app.db_roles` (api, in
`api/Procfile`) and `npm run db:roles` (app, predeploy). It creates `app_rw`, which can
read and write rows but can't change the schema, isn't a superuser and can't bypass RLS.
When `APP_DB_PASSWORD` is set, it also creates `app_rw_login`, the login the app should
use. Migrations keep running as the owner via `MIGRATION_DATABASE_URL`.

Cut-over, per service (`tastetrace-api` with `tastetrace-api-db`, `tastetrace` with `Postgres`):

1. Deploy the branch once with no variable changes. The role step runs and nothing else changes.
2. Add a random `APP_DB_PASSWORD` (e.g. `openssl rand -base64 32`) as a **sealed** variable on the service.
3. Set `MIGRATION_DATABASE_URL=${{<db>.DATABASE_URL}}` (the owner, for migrations and the role step).
4. Set `DATABASE_URL=postgresql://app_rw_login:${{APP_DB_PASSWORD}}@${{<db>.PGHOST}}:${{<db>.PGPORT}}/${{<db>.PGDATABASE}}`.
5. Redeploy, then check: health returns 200, sign in works, and logging a meal works.

**Rollback:** set `DATABASE_URL` back to `${{<db>.DATABASE_URL}}` and redeploy.
**Rotate the password:** change `APP_DB_PASSWORD` and redeploy. The role step re-sets it.

## api/

See `api/README.md`. The mobile backend: fastapi-users auth (form-encoded
bearer login), async SQLAlchemy, Alembic migrations run on deploy.

```sh
cd api
uv sync
uv run pytest
uv run uvicorn app.main:app --reload --port 8000
```

## ios/

See `ios/README.md`. The Xcode project is committed, so just open the
workspace:

```sh
open ios/TasteTrace.xcworkspace
```

It is generated from `ios/project.yml` by XcodeGen. Change the spec, run
`xcodegen generate`, and commit both together.

## landing/

Open `landing/index.html` directly, or serve the folder with any static server.
