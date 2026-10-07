# tastetrace

Two services in one Railway project, plus the iOS client. Each service builds
from its own root directory and redeploys on pushes to `main`.

| Folder | What it is | Railway service | Domain |
| --- | --- | --- | --- |
| `landing/` | Static waitlist landing page (`index.html`, no build step) | `landing` | https://tastetrace.up.railway.app (later tastetrace.app) |
| `api/` | The backend: FastAPI + Postgres (SQLAlchemy/Alembic) | `tastetrace-api` | https://tastetrace-api-production.up.railway.app |
| `ios/` | Native SwiftUI app; open `ios/TasteTrace.xcworkspace` | — | — |

The landing page runs on its Railway domain for now. Its custom domains are
already attached in Railway and start working once their DNS records are added.

The landing page's waitlist form posts to the API's `/api/waitlist`, which stores
signups in the `waitlist_signups` table.

The Express + React web application in `app/` was retired on 2026-10-07. The iOS
app had already moved to the FastAPI backend, so the web app's only remaining job
was the waitlist, which now lives in `api/`. Its Railway service and database
were deleted; the waitlist rows were exported first and loaded into the API
database.

## Database roles (least privilege)

> **Status: code ready; not yet applied in production.**
> Until the cut-over below, the API still connects as the `postgres` superuser.

Each deploy runs a role step after migrations: `python -m app.db_roles`, from
`api/Procfile`. It creates `app_rw`, which can
read and write rows but can't change the schema, isn't a superuser and can't bypass RLS.
When `APP_DB_PASSWORD` is set, it also creates `app_rw_login`, the login the app should
use. Migrations keep running as the owner via `MIGRATION_DATABASE_URL`.

Cut-over for `tastetrace-api` with `tastetrace-api-db`:

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

## License

TasteTrace is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE.md).
Copyright 2026 The TasteTrace founders. This covers everything in this repository, including the API, web app, landing page, and iOS app.

- **Noncommercial use is free.** Personal study, learning, hobby projects, schools, and nonprofits may
  use, copy, modify, and share the code, as long as they include the license and its `Required Notice:` line.
- **Commercial use is reserved to the founders,** who keep all rights to the code and the product. To ask
  about commercial use, open an issue on this repository.
- Third-party libraries and assets keep their own licenses.
