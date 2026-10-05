# TasteTrace: security and production gaps

This list comes from the October 2026 audit against the class
[Production Standard](../.claude/skills/production-standard/references/standard.md).
Rule IDs (AUTH-3, FE-1, …) point to that file.

- **Fixed:** changed on branch `security/production-standard`.
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

## Open: student tasks

| Rule | Sev | Where | Problem | Suggested fix |
|---|---|---|---|---|
| PRIV-1 / PRIV-3 | **High** | `landing/index.html`, App Store listing | There's no privacy policy, though the product collects emails and **health data** (symptoms, sensitivities). App Store submission needs a privacy-policy URL. | **Owner action (teacher):** approve wording. Then link it from the landing page, the web sign-up and the iOS sign-up. |
| FE-6 | Med | `app/client/src/components/home/Testimonials.tsx` | 5-star testimonials with initials for a product that hasn't launched. They look invented. | Remove them, or label them clearly as illustrative. |
| FE-6 / AUTH | Med | `app/server/routes/index.ts:65` | Web "forgot password" says an email was sent but sends nothing. | Either build reset (copy the API's token flow) or say "contact support" honestly. |
| DB-2 | Med | `.railway/railway.ts:24` (`npm run db:push`) | The web schema is pushed with no migration history; a rename or drop can silently lose data. | Switch to `drizzle-kit generate` + `migrate` with committed files. Drop `api_tokens` in a reviewed migration. |
| AUTH-2 | Med | `api/` | Emails are never verified. | fastapi-users has a verify router. Require verification before data sharing or export. |
| OPS-5 | Med | `ios/Config/Debug.xcconfig:9` | Debug builds talk to the **production** API, so test data lands in prod. | Point Debug at a staging API (a Railway `staging` environment). |
| AUTH-3 | Low | `api/app/ai/synthesis.py:39` | The AI throttle dict `_last_generated` never shrinks. | Evict old entries, using the same pattern as `rate_limit.py`. |
| API-1 | Low | `api/app/routers/meals.py:36` | `dish_id` on a meal isn't checked against the user. This is a data-integrity issue, not a leak. | Verify that the dish belongs to `user.id`, or 404. |
| API-2 | Low | `api/app/services/export.py` | CSV cells starting with `= + - @` aren't neutralised (formula injection once the practitioner sharing feature exists). | Prefix those cells with `'`. |
| DB-4 | Low | `api/app/db.py`, `app/server/db.ts` | No explicit TLS. | Confirm both `DATABASE_URL`s use `*.railway.internal`. |
| DB-2 | Low | `api/migrations/env.py:30` | `set_main_option` breaks if the DB password contains `%`. | Escape `%` as `%%`. |
| FE-7 | Low | `ios/TasteTrace/Info.plist:29` | `NSAllowsLocalNetworking` ships in Release. | Move it to a Debug-only plist or xcconfig. |
| FE-7 | Low | `ios/.../AppEnvironment.swift:34` | The fallback base URL is `http://localhost:5000`, the old Express port. | Fail loudly if `API_BASE_URL` is missing. |
| FE-7 | Low | `ios/.../ReminderScheduler.swift` | Local reminders keep firing after sign-out or delete. | Cancel all pending notifications in sign-out and delete. |
| FE-4 | Low | `app/client/index.html:5` | `maximum-scale=1` blocks pinch-zoom. | Remove it. |
| FE-4 | Low | iOS `Info.plist` | Portrait-only and light-mode-only. | Revisit for accessibility (Dynamic Type, dark mode). |
| FE-5 | Low | landing / app / iOS | Three different visual systems: Fraunces + Plex, Inter + navy shadcn, and `TTColor`. | Pick one token set and share it. |
| OPS-2 | Low | `app/` (tailwindcss 3 → braces) | High advisory in a build-time dependency. CI blocks on critical only until it's fixed. | Upgrade to Tailwind 4, then raise the CI audit level to `high`. |
| OPS-1 | Low | `.github/workflows/ios-testflight.yml:11,40` | It uploads to TestFlight from the `taylor` branch as well as `main`, and pins neither the setup-xcode action nor Xcode. | Upload from `main` only; pin `xcode-version`. |
| API-9 | Low | `.railway/railway.ts` (web) | The web app's health check is `/` (static HTML). | Add `/api/health` with a DB ping. |
| — | Low | `README.md` | Web and iOS are two separate account systems. | Decide whether the web app moves to the Python API. |

## Owner actions (settings, not code)

| Rule | Where | Action |
|---|---|---|
| OPS-1 | `.railway/railway.ts` (`checkSuites: false` ×3) and Railway dashboard | Turn on **Wait for CI**, so a red build never deploys. |
| OPS-3 | GitHub → Settings → Code security | Secret scanning and push protection on. |
| OPS-4 | GitHub → Settings → Rules | Protect `main`: PR required, the `CI / api` and `CI / app` checks must pass. |
| DB-5 | Railway → both Postgres services → Backups | Turn on scheduled backups and rehearse one restore. |
| OPS-6 | Sentry (free tier) and an uptime monitor | Error tracking, plus a monitor on `/api/health`. |
| PRIV-1 | Teacher / school | Approve the privacy-policy text (health data). |
| — | Railway env (`api`) | `ANTHROPIC_API_KEY`, `RESEND_API_KEY` and `PASSWORD_RESET_ENABLED` are set in the dashboard but not listed in `railway.ts`. Confirm the intended values. |
