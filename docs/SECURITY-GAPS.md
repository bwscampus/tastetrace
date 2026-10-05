# TasteTrace: security and production gaps

This list comes from the October 2026 audit against the class
Production Standard (the global `production-standard` Claude Code skill).
Rule IDs (AUTH-3, FE-1, …) refer to its rules.

- **Fixed:** changed on branch `security/production-standard`, or on
  `security/db-hardening` (branched from it) for the database items in their own section below.
- **Open:** a student task. Pick one, fix it with a test, and update this row.
- **Owner action:** a GitHub, Railway, App Store or legal setting. It can't be fixed in code.

Run the `production-standard` skill (Claude Code) before finishing any change to auth,
the database, API routes, rendering, or deploy config. It re-checks these rules.

## What's already good

- No SQL injection paths: the API uses the ORM everywhere, and Drizzle `sql` templates are parameterized.
- Password hashing:
  - API: Argon2 via pwdlib, minimum length 8, and the password can't contain the email.
  - Web: scrypt with a random salt and a timing-safe compare.
- Revocable database sessions. A password reset signs out every device.
- The iOS token lives in the Keychain (`AfterFirstUnlockThisDeviceOnly`).
- Every API query is scoped to its owner and returns 404 for foreign rows (`api/app/deps.py`), with tests.
- The API sends a strict CSP, HSTS and nosniff, has a CORS allowlist, hides its docs in prod, and returns generic 500s with a request ID.
- The API refuses to boot in production with a placeholder secret, wildcard hosts or an http base URL.
- The Anthropic key never leaves the server.
- No secrets are committed, and `.env` is gitignored.

## Fixed in this branch

| Rule | Sev | Where | What changed |
|---|---|---|---|
| AUTH-3 | High | `api/app/rate_limit.py` | The iOS login (`/api/auth/bearer/login`) had no rate limit. It is now limited like the cookie login, and `PATCH`/`DELETE /api/users/me` are limited too. |
| AUTH-3 | High | `app/server/rateLimit.ts`, `app/server/auth.ts` | The web login, register and waitlist had no rate limit. They now use `express-rate-limit`. |
| AUTH-6 | High | `api/app/auth/account.py`, `ios/.../ProfileView.swift` | Users couldn't delete their account, which the App Store requires (guideline 5.1.1(v)). Added `DELETE /api/users/me` (password-confirmed, data removed by cascade) and an in-app **Delete Account** button. |
| AUTH-3 | Med | `api/app/rate_limit.py` | Limits keyed on the client-controlled `X-Forwarded-For`, and the bucket dict grew without bound. Now keys on `X-Real-IP` (Railway overwrites it) and caps memory. |
| AUTH-5 | Med | `api/app/auth/account.py` | `PATCH /api/users/me` changed email or password without the current password. Now requires `currentPassword`, and a password change signs out the other sessions. |
| AUTH-3 | Med | `app/server/tokenAuth.ts` (deleted) | Unused legacy mobile token routes (180-day tokens, no rate limit). Removed. |
| AUTH-4 / API-6 | Med | `app/server/auth.ts` | The web session cookie had no `SameSite`. It is now explicitly `Lax`, and boot fails without `SESSION_SECRET`. |
| API-2 / AUTH-7 | Med | `app/server/auth.ts`, `database-storage.ts` | Web register didn't validate or lowercase emails, and lookups were case-sensitive, so duplicate accounts were possible. Emails are now validated and lowercased, lookups are case-insensitive, and the password minimum is 8 (the form matches). |
| API-4 | Med | `app/server/app.ts` | The web app sent no security headers. Added `helmet` (strict CSP in production), turned off `x-powered-by`, and added a 100kb body limit. |
| API-8 | Med | `app/server/app.ts` | The request log printed response bodies, including partial tokens and emails. It now logs method, path, status and timing only. |
| API-3 | Low | `app/server/app.ts` | 500 responses echoed `err.message`. They now return a generic message. |
| API-8 | Low | `api/app/email/resend_client.py`, `app/server/routes/index.ts` | Recipient and reset email addresses were logged. Removed. |
| API-8 | Low | `api/app/logging.py` | A client `X-Request-ID` was logged unchecked. It must now match `[A-Za-z0-9-]{1,64}`. |
| API-9 | Low | `api/app/routers/health.py` | The health check didn't touch the DB and exposed the environment and version. It now runs `SELECT 1`, returns 503 on failure, and reports nothing else. |
| API-2 | Low | `api/app/schemas.py` | Unbounded `notes`, `tz`, `severity`, `ingredients` and `ingredient_details` fields. All now have length or size caps. |
| FE-6 | Med | `landing/index.html` | The waitlist showed success even when the save failed. It now confirms only on `res.ok` and shows an error otherwise. |
| FE-7 | Med | `ios/.../AuthSession.swift`, `JSONFileStore.swift` | Cached days, dishes and watchlist survived sign-out. Sign-out, delete and 401 now wipe every cache file. Files are written with data protection and excluded from backup. |
| OPS-1 | Med | `.github/workflows/ci.yml` | No CI for `api/` or `app/`. Added pytest, alembic on real Postgres and pip-audit; tsc, vitest (DB-backed), build and npm audit. |
| OPS-2 | Low | `.github/dependabot.yml` | Weekly update PRs for uv, npm and Actions. Patched pyjwt (PYSEC-2026-4141) and ran `npm audit fix`. |
| | Low | `app/server/replitAuth.ts` (deleted) | Unused auth module, removed. Pre-existing type errors fixed so `npm run check` is a usable gate. |

## Fixed in `security/db-hardening` (production cut-over pending)

| Rule | Sev | Where | What changed |
|---|---|---|---|
| DB-8 | High | `api/app/auth/tokens.py`, `api/app/auth/backend.py`, migration `0004_hash_access_tokens` | `access_tokens` stored the raw session token (cookie and iOS bearer) as its primary key, so anyone who could read the database or a backup could sign in as every logged-in user. It now stores `base64url(sha256(token))`. Migration 0004 hashes existing rows in place, so nobody is signed out. Tests prove a stored hash can't be used as a token. |
| DB-6 | Med | `api/app/db_roles.py`, `app/server/scripts/ensure-app-role.ts` | Both apps connected as the `postgres` superuser, which can do anything, bypasses RLS, and can drop every table. Each deploy now creates `app_rw` (data read/write only, no DDL, no superuser, no BYPASSRLS) and, with `APP_DB_PASSWORD`, the login `app_rw_login`. Migrations use `MIGRATION_DATABASE_URL` (owner). Verified against Postgres 16: both apps' integration flows pass as `app_rw_login`. **Takes effect only after the cut-over in the README.** |
| — | Low | `api/migrations/env.py` | Alembic broke if the DB password contained `%`. The URL is now escaped. |

## Fixed in `security/hardening-round-1`

| Rule | Where | Fix |
|---|---|---|
| FE-6 | `app/client/src/components/home/Testimonials.tsx` | Fabricated 5-star testimonials removed from the web Home and Landing pages. |
| FE-6 / AUTH | `app/server/routes/index.ts:65` | Web "forgot password" no longer claims an email was sent. It says web reset isn't available yet and to contact the team (web accounts are separate from the iOS app). Same reply for every address; the address is never looked up or logged. |
| AUTH-3 | `api/app/ai/synthesis.py:39` | AI throttle memory is bounded: stale entries evicted, hard cap of 10k (`test_hardening.py`). |
| API-1 | `api/app/routers/meals.py:36` | A meal's `dishId` must be the caller's own dish, else 404 (`test_a_meal_cannot_point_at_someone_elses_dish`). |
| API-2 | `api/app/services/export.py` | CSV cells starting with `= + - @`, tab or CR get a leading `'` (formula injection). |
| DB-2 | `api/migrations/env.py:30` | Already fixed in db-hardening: the URL's `%` is escaped as `%%`. |
| FE-7 | `ios/TasteTrace/Info.plist:29` | `NSAllowsLocalNetworking` is Debug-only (`ios/Config/Info-Debug.plist`); Release has no ATS exception (checked in built app). |
| FE-7 | `ios/.../AppEnvironment.swift:34` | Missing/invalid `API_BASE_URL` fails loudly (`assertionFailure`); no silent `http://localhost:5000` fallback. |
| FE-7 | `ios/.../ReminderScheduler.swift` | All pending and delivered reminders are cancelled on sign-out, account deletion and 401 (`AuthSession.onSessionEnded`). |
| FE-4 | `app/client/index.html:5` | `maximum-scale=1` removed; pinch-zoom works. |
| OPS-1 | `.github/workflows/ios-testflight.yml:11,40` | TestFlight uploads from `main` only; `setup-xcode` pinned to a commit (v1.7.0) and Xcode to 26.3. |
| API-9 | `.railway/railway.ts` (web) | Web app has `GET /api/health` (DB ping, `{status}` only, 503 on failure); `railway.ts` health check points at it. **Owner:** set the live Railway health check path to `/api/health` (repo config isn't auto-applied). |

Out of scope for round 1 (still open above): email verification, Drizzle migrations instead of `db:push`, a staging environment (Debug builds still hit the production API), field-level encryption, duplicate health data across the two databases, RLS, the Tailwind 4 upgrade, and the design-system unification.

## Open: student tasks

| Rule | Sev | Where | Problem | Suggested fix |
|---|---|---|---|---|
| PRIV-1 / PRIV-3 | **High** | `landing/index.html`, App Store listing | There's no privacy policy, though the product collects emails and **health data** (symptoms, sensitivities). App Store submission needs a privacy-policy URL. | **Owner action (teacher):** approve wording. Then link it from the landing page, the web sign-up and the iOS sign-up. |
| DB-2 | Med | `.railway/railway.ts:24` (`npm run db:push`) | The web schema is pushed with no migration history; a rename or drop can silently lose data. | Switch to `drizzle-kit generate` + `migrate` with committed files. Drop `api_tokens` in a reviewed migration. |
| AUTH-2 | Med | `api/` | Emails are never verified. | fastapi-users has a verify router. Require verification before data sharing or export. |
| OPS-5 | Med | `ios/Config/Debug.xcconfig:9` | Debug builds talk to the **production** API, so test data lands in prod. | Point Debug at a staging API (a Railway `staging` environment). |
| DB-4 | Low | `api/app/db.py`, `app/server/db.ts` | No explicit TLS. | Confirm both `DATABASE_URL`s use `*.railway.internal`. |
| FE-4 | Low | iOS `Info.plist` | Portrait-only and light-mode-only. | Revisit for accessibility (Dynamic Type, dark mode). |
| FE-5 | Low | landing / app / iOS | Three different visual systems: Fraunces + Plex, Inter + navy shadcn, and `TTColor`. | Pick one token set and share it. |
| OPS-2 | Low | `app/` (tailwindcss 3 → braces) | High advisory in a build-time dependency. CI blocks on critical only until it's fixed. | Upgrade to Tailwind 4, then raise the CI audit level to `high`. |
| — | Low | `README.md` | Web and iOS are two separate account systems. | Decide whether the web app moves to the Python API. |
| PRIV-3 / DB-7 | Med | `api` + `app` databases: `symptoms.notes`, `meals.notes`, `ai_syntheses.text` | Free-text health notes and AI health summaries are stored as plain text. Railway encrypts the disk, but anyone with database access (a dump, a leaked credential) can read them. | Field-level encryption (e.g. AES-GCM via `cryptography`, key in a sealed Railway variable, key ID stored with each value). Encrypt only free text; structured fields are needed for the correlation queries. |
| DB-7 | Med | `api` and `app` databases | The same kind of health data lives in **two** databases (web and mobile), doubling what can leak and what a deletion request must cover. | Move the web app onto the Python API (see the row above) and retire the web copy of the health tables. |
| DB-6 | Low | all user tables | No row-level security. Isolation relies on every query filtering by `user_id` (tested). Now that the app runs as a non-superuser role, RLS would actually be enforced. | Optional defense in depth: `ENABLE ROW LEVEL SECURITY` + a `user_id = current_setting('app.user_id')::uuid` policy, with the app setting `app.user_id` per request. |
| DB-2 | Low | `app/shared/schema.ts:36-53` | The retired `api_tokens` table is still defined (kept so `db:push` doesn't drop it) and may still hold old token hashes. | Once `drizzle generate` migrations replace `push`, drop it in a reviewed migration. |

## Owner actions (settings, not code)

| Rule | Where | Action |
|---|---|---|
| OPS-1 | `.railway/railway.ts` (`checkSuites: false` ×3) and Railway dashboard | Turn on **Wait for CI**, so a red build never deploys. |
| OPS-3 | GitHub → Settings → Code security | Secret scanning and push protection on. |
| OPS-4 | GitHub → Settings → Rules | Protect `main`: PR required, the `CI / api` and `CI / app` checks must pass. |
| DB-5 | Railway → both Postgres services → Backups | ✅ Done 2026-10-05: daily (6-day) + weekly (27-day) snapshots and point-in-time recovery on `tastetrace-api-db` and `Postgres`. Still to do: rehearse one restore (`railway postgres pitr restore --at 1h` into a new service, check it, delete it). |
| OPS-6 | Sentry (free tier) and an uptime monitor | Error tracking, plus a monitor on `/api/health`. |
| DB-6 | Railway → `tastetrace-api` and `tastetrace` services | After `security/db-hardening` is deployed, do the least-privilege cut-over in the README ("Database roles"). Until then both apps still connect as `postgres`. |
| PRIV-1 | Teacher / school | Approve the privacy-policy text (health data). |
| — | Railway env (`api`) | `ANTHROPIC_API_KEY`, `RESEND_API_KEY` and `PASSWORD_RESET_ENABLED` are set in the dashboard but not listed in `railway.ts`. Confirm the intended values. |
