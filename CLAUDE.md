# TasteTrace: notes for Claude

- `api/`: FastAPI + Postgres (Railway). The iOS app's backend. Tests: `cd api && uv run pytest`.
- `app/`: Express + React/Vite web app with its own Postgres. Gates: `cd app && npm run check && npm test && npm run build`
  (`npm test` runs the DB-backed API tests only when `DATABASE_URL` is set).
- `ios/`: SwiftUI app; local packages under `ios/Packages/*` (`swift test` in each).
- `landing/`: static page; its waitlist form posts to `app`'s `/api/waitlist`.

## Production Standard

Before finishing any change that touches auth, accounts, the database or migrations, API routes,
rendering of user data, uploads, logging, env/deploy config, or CI, run the
**`production-standard`** skill (`.claude/skills/production-standard/`). Don't call work done
while a Critical or High finding is open. Track Medium/Low findings in `docs/SECURITY-GAPS.md`.
