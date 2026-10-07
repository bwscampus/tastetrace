# TasteTrace: notes for Claude

- `api/`: FastAPI + Postgres (Railway). The only backend. Tests: `cd api && uv run pytest`.
- `ios/`: SwiftUI app; local packages under `ios/Packages/*` (`swift test` in each).
- `landing/`: static page; its waitlist form posts to the API's `/api/waitlist`.

The Express + React web app in `app/` was retired on 2026-10-07. Its one
surviving responsibility, the landing page's waitlist, moved to
`api/app/routers/waitlist.py`.

## Production Standard

Before finishing any change that touches auth, accounts, the database or migrations, API routes,
rendering of user data, uploads, logging, env/deploy config, or CI, run the
global **`production-standard`** skill (and **`database-security`** for database, migration, or
Railway DB changes). Don't call work done
while a Critical or High finding is open. Track Medium/Low findings in `docs/SECURITY-GAPS.md`.
