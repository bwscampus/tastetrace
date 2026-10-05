# Deploy / CI checks

## OPS-1: CI workflow templates

**Python (uv + FastAPI)**: `.github/workflows/ci.yml`
```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env: { POSTGRES_PASSWORD: postgres, POSTGRES_DB: app }
        ports: ["5432:5432"]
        options: >-
          --health-cmd pg_isready --health-interval 5s --health-timeout 5s --health-retries 10
    env:
      ENVIRONMENT: test
      DATABASE_URL: postgresql+asyncpg://postgres:postgres@localhost:5432/app
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v6
      - run: uv sync --frozen
      - run: uv run pytest
      - run: uv run alembic upgrade head   # real Postgres catches SQLite-only assumptions
      - run: uvx pip-audit -r <(uv export --frozen --no-hashes --no-dev)
```

**Node**: add to the job: `npm ci`, `npm run typecheck`, `npm run lint`, `npm test`,
`npm run build`, `npm audit --omit=dev --audit-level=high`.

Monorepos: one job per package, with `paths:` filters so an iOS-only commit doesn't run web CI.

## OPS-2: `.github/dependabot.yml`

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule: { interval: "weekly" }
  - package-ecosystem: "npm"          # or "uv" / "pip"
    directory: "/"
    schedule: { interval: "weekly" }
    open-pull-requests-limit: 5
```

## Owner actions (settings, not code)

List these for the human. You can't do them from the repo:

| Rule | Where | Action |
|---|---|---|
| OPS-3 | GitHub → Settings → Code security | Secret scanning + push protection on |
| OPS-4 | GitHub → Settings → Rules | Protect `main`: PR required, CI must pass, 1 review |
| OPS-1 | Railway → Service → Settings → Deploy | "Wait for CI" on (`checkSuites: true` in `railway.ts`) |
| DB-5 | Railway (Pro) → Postgres → Backups, or `railway postgres pitr schedule set --daily --weekly` + `railway postgres pitr enable` | Snapshots + point-in-time recovery on; practice one restore (`railway postgres pitr restore --at 1h`) |
| DB-6 | Railway → app service → Variables | Sealed `APP_DB_PASSWORD`; `MIGRATION_DATABASE_URL` = owner URL; `DATABASE_URL` = `app_rw_login` URL |
| OPS-5 | Railway → Environments | Separate `staging` env with its own DB |
| OPS-6 | Sentry (free) + an uptime monitor | Point the monitor at `/api/health` |
| OPS-7 | README | Rollback steps: Railway → Deployments → previous → Redeploy |

## Railway specifics

- Client IP: use `X-Real-IP` (Railway overwrites it at the edge).
- `--forwarded-allow-ips='*'` on uvicorn is OK *only* because Railway is the only thing in front.
- Health check path should hit an endpoint that pings the DB (API-9).
- Migrations run in the start command (`alembic upgrade head && uvicorn …`), so a failed migration
  fails the deploy instead of serving a broken app.
- Prefer the private `*.railway.internal` `DATABASE_URL` for app → DB traffic (DB-4).
- Persistent uploads need a Railway Volume or object storage (S3/R2); container disk is wiped
  on redeploy.

## Vercel specifics

- Turn on Deployment Protection for previews (OPS-5).
- Use the Vercel Firewall rate-limit rules for credential routes as a second layer (AUTH-3).
- Set Spend Management alerts.
