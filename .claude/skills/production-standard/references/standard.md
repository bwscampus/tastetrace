# Production Standard

This is the bar every class project must clear before real users (and real data) touch it.
It is a condensed version of what a respectable seed-stage startup ships with, drawn from
the OWASP Top 10:2025, the OWASP API Security Top 10, OWASP ASVS 5.0 Level 1, the OWASP
cheat sheets, and the Railway / Vercel / GitHub production guidance (sources at the bottom).

Every rule has an ID. Code reviews, the `production-standard` agent skill, and each repo's
`docs/SECURITY-GAPS.md` cite these IDs, so "fails AUTH-3" means the same thing everywhere.

**Severity guide**

| Severity | Meaning | Ship? |
|---|---|---|
| Critical | Anyone on the internet can take over accounts, read other people's data, or run code. | Stop. Fix now. |
| High | A realistic attack hurts users or the business (stolen credits, admin takeover, brute force), or a store/legal requirement is unmet. | Not until fixed. |
| Medium | Defense-in-depth missing, or abuse is possible but limited. | Fix this sprint. |
| Low | Hygiene, polish, future-proofing. | Track it. |

---

## DB: Database

| ID | Rule | Why / source |
|---|---|---|
| DB-1 | **Parameterised queries only.** Use the ORM or `$1` placeholders; never build SQL with f-strings or `+`. Column names that must be dynamic come from a hard-coded allowlist. | OWASP A05 Injection |
| DB-2 | **Versioned migrations.** Every schema change is a reviewed file (Alembic, SQL files, Drizzle `generate`), applied automatically on deploy. No `db push` against production. Destructive statements (`DROP`, column removal) need a deliberate, separate migration. | Lost data is unrecoverable |
| DB-3 | **Secrets live in the platform's env vars only.** `.env` is gitignored; `.env.example` holds placeholders. A secret that was ever committed (or sits in a public repo's client code) is burned: rotate it. | OWASP A04 Cryptographic Failures; GitHub secret scanning |
| DB-4 | **Encrypted or private connection to the database.** Use Railway's private `*.railway.internal` host, or TLS with certificate verification. `rejectUnauthorized: false` on a public host is not TLS. | OWASP A04 |
| DB-5 | **Backups on, restore rehearsed.** Enable the platform's scheduled backups and do one practice restore into a scratch database. Write the steps in the README. On Railway (Pro plan): daily + weekly snapshot schedules, plus point-in-time recovery (`railway postgres pitr enable`), which lets you restore to any second in roughly the last 4 weeks. | Railway / Vercel production checklists |
| DB-6 | **Least privilege.** The running app connects as a role that can only read and write rows (`SELECT/INSERT/UPDATE/DELETE`): no DDL, not superuser, no `BYPASSRLS`. Migrations run as the owner via a separate `MIGRATION_DATABASE_URL`. An idempotent step after migrations (re)creates the role and grants on every deploy. If an attacker gets SQL execution through the app, they can't drop tables or read other databases. | ASVS L1 config; OWASP A01 |
| DB-7 | **Know your PII.** List what personal data you store and why. Don't collect what you don't need. Encrypt especially sensitive free text (health notes, minors' journals) at the application level when the threat model calls for it. | OWASP A06 Insecure Design |
| DB-8 | **Store only hashes of tokens.** Session, API, reset, and verification tokens are stored as SHA-256 hashes, never raw, so a leaked database or backup can't be replayed to log in as users. | OWASP Session Management Cheat Sheet |

> **About RLS (row-level security):** RLS makes Postgres itself enforce "users only see their own rows". It
> has **no effect when the app connects as a superuser or table owner**, which is the default on Railway. Get
> DB-6 right first. RLS is then a useful backstop for multi-tenant data, and it's mandatory if clients ever
> query the database directly (e.g. Supabase).

## AUTH: Accounts and sessions

| ID | Rule | Why / source |
|---|---|---|
| AUTH-1 | **Strong password hashing:** Argon2id (preferred), scrypt, or bcrypt cost ≥ 12. Minimum length 8. Never home-grown hashing. | OWASP Password Storage Cheat Sheet |
| AUTH-2 | **Verify the email before it grants anything.** An unverified email must not unlock money, credits, history, or admin rights. | OWASP A07 Authentication Failures |
| AUTH-3 | **Rate-limit every credential endpoint:** login (cookie *and* token/bearer variants), register, password reset, resend-verification. Key on a header your platform guarantees (Railway: `X-Real-IP`). The limiter's memory must be bounded. Return **429**. | OWASP API4 Unrestricted Resource Consumption |
| AUTH-4 | **Sessions:** cookie is `HttpOnly`, `Secure` (prod), `SameSite=Lax` or stricter; the server can revoke it; logout revokes it. Tokens on mobile live in the Keychain / Keystore, never plain storage. | ASVS L1 session management |
| AUTH-5 | **Sensitive account changes need the current password** (email, password, delete). Changing the password logs out other sessions. | OWASP A07 |
| AUTH-6 | **Self-service account deletion** that removes the user's data. Required by the Apple App Store and expected under COPPA/GDPR. | App Store Review Guideline 5.1.1(v) |
| AUTH-7 | **No account enumeration.** Login, reset, and signup responses don't reveal whether an email is registered. | OWASP A07 |
| AUTH-8 | **Admin rights only go to verified identities.** Never "whoever signs up with this email first". | OWASP A01 Broken Access Control |

## API: Server endpoints

| ID | Rule | Why / source |
|---|---|---|
| API-1 | **Object-level authorization on every ID.** Every query that takes an ID from the request also filters by the signed-in owner; foreign rows return 404. Admin routes check admin first. | OWASP API1 BOLA (#1 API risk) |
| API-2 | **Validate all input, including size.** Typed schemas (Pydantic, zod, hand-written validators) with length/size caps on every string, list, and JSON body. | OWASP API4, A05 |
| API-3 | **Generic errors.** No stack traces, SQL errors, or `err.message` from 500s reach the client. Log details server-side with a request ID. | OWASP A10 Mishandling of Exceptional Conditions |
| API-4 | **Security headers on every response:** `Content-Security-Policy` (no `unsafe-inline` scripts), `Strict-Transport-Security` (prod), `frame-ancestors 'none'` / `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`. Hide `X-Powered-By`. | OWASP A02 Security Misconfiguration; Vercel checklist |
| API-5 | **CORS is an explicit allowlist**, never `*` with credentials; off when the frontend is same-origin. | OWASP A02 |
| API-6 | **CSRF:** cookie-authenticated, state-changing routes rely on `SameSite=Lax` cookies *and* JSON-only bodies or an Origin check. | ASVS L1 |
| API-7 | **Uploads:** authenticated (or tightly rate-limited), size-capped, content-sniffed (don't trust the declared type), random filenames, orphan cleanup. | OWASP File Upload Cheat Sheet |
| API-8 | **No secrets or PII in logs.** Never log tokens, reset links, passwords, response bodies, or email addresses. Log user IDs. | OWASP A09 Logging & Alerting Failures |
| API-9 | **Health check tells the truth:** pings the database, returns 503 if it's down, and exposes nothing about environment or versions. | Railway healthchecks |
| API-10 | **Production config is validated at startup:** refuse to boot with placeholder secrets, wildcard hosts, missing email keys, or `http://` base URLs. | OWASP A02 |

## FE: Frontend and mobile

| ID | Rule | Why / source |
|---|---|---|
| FE-1 | **Never put user data into HTML unescaped.** Use `textContent`, framework rendering (React/SwiftUI), or an `escapeHtml()` helper. `innerHTML`/`dangerouslySetInnerHTML` only with constants or escaped values. | OWASP A05 (XSS) |
| FE-2 | **No secrets in client code.** Anything in JS, `NEXT_PUBLIC_*`, `Info.plist`, or the app bundle is public. AI and payment keys stay on the server. | OWASP A04 |
| FE-3 | **The server enforces anything that matters.** Paywalls, roles, credits, and limits are checked server-side; the client only hides buttons. | OWASP A01 |
| FE-4 | **Accessible basics:** every input has a `<label>` (or `aria-label`), visible focus styles, alt text, no `maximum-scale=1` zoom lock, color contrast ≥ WCAG AA. | WCAG 2.2 AA |
| FE-5 | **One design system:** colors, type, and spacing come from one token source (CSS variables / Tailwind config / theme struct) and shared components, not inline `style=` scattered through markup. | Maintainability; enables strict CSP |
| FE-6 | **Honest UI:** success messages only after the server confirms success; no fabricated testimonials, ratings, or user counts. | FTC endorsement rules; trust |
| FE-7 | **Mobile data hygiene:** tokens in Keychain; all cached user data cleared on sign-out/delete; sensitive files use data protection; debug builds never talk to the production API. | OWASP MASVS |

## PRIV: Privacy and legal

| ID | Rule | Why / source |
|---|---|---|
| PRIV-1 | **A privacy policy is linked wherever you collect data** (signup, waitlist, app store listing): what you collect, why, who sees it, how to delete it. | App Store, COPPA, state privacy laws |
| PRIV-2 | **Under-13 users need verifiable parental consent** before you collect personal information (US COPPA). If you serve minors, decide your age gate with your teacher. | FTC COPPA Rule |
| PRIV-3 | **Health, mental-health, and minors' data are sensitive:** minimise it, never put it in logs or analytics, and give users export and delete. | FTC Health Breach Notification Rule; GDPR Art. 9 |

## OPS: Deployment and operations

| ID | Rule | Why / source |
|---|---|---|
| OPS-1 | **CI gate on every push and PR:** tests, lint, typecheck, build, dependency audit. The deploy waits for CI to pass (Railway "Wait for CI"). | OWASP A03 Supply Chain; Vercel checklist |
| OPS-2 | **Lockfiles committed + Dependabot on** (app dependencies and GitHub Actions). | OWASP A03 |
| OPS-3 | **GitHub secret scanning + push protection on.** | GitHub docs |
| OPS-4 | **`main` is protected:** PRs only, CI must pass, at least one reviewer (teammate or teacher). | OWASP A08 Integrity Failures |
| OPS-5 | **Staging is separate from production:** its own database and env vars; preview/staging URLs not indexed; test data never lands in prod. | Vercel / Railway environments |
| OPS-6 | **You find out about errors before users tell you:** error tracking (e.g. Sentry free tier) and an uptime monitor on the health check. | OWASP A09 |
| OPS-7 | **Rollback is documented and rehearsed:** you know how to redeploy the previous version in under 5 minutes. | Vercel Instant Rollback; Railway deployments |

---

## Sources

- OWASP Top 10:2025: https://owasp.org/Top10/2025/
- OWASP API Security Top 10 (2023): https://owasp.org/API-Security/
- OWASP ASVS 5.0: https://owasp.org/www-project-application-security-verification-standard/
- OWASP Password Storage Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html
- OWASP File Upload Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html
- OWASP Session Management Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html
- Railway encryption at rest (staff): https://station.railway.com/questions/are-databases-encrypted-at-rest-0e719d6c
- Railway Postgres backups and PITR: https://docs.railway.com/guides/postgres-backups-restores
- Vercel production checklist: https://vercel.com/docs/production-checklist
- Railway best practices: https://docs.railway.com/overview/best-practices
- Railway staff on `X-Real-IP` / `X-Forwarded-For`: https://station.railway.com/questions/security-critical-questions-on-edge-prox-8fddd775
- GitHub secret scanning: https://docs.github.com/code-security/secret-scanning/about-secret-scanning
- Apple App Store account deletion: https://developer.apple.com/support/offering-account-deletion-in-your-app/
- FTC COPPA: https://www.ftc.gov/legal-library/browse/rules/childrens-online-privacy-protection-rule-coppa
