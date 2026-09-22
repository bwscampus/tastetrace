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

- `DATABASE_URL` – Postgres connection string (on Railway: `${{Postgres.DATABASE_URL}}`)
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

See `ios/README.md`. Generate the project, then open the workspace:

```sh
cd ios
xcodegen generate && open TasteTrace.xcworkspace
```

## landing/

Open `landing/index.html` directly, or serve the folder with any static server.
