---
name: production-standard
description: Check a class startup codebase against the Production Standard (database security, API hardening, frontend safety, privacy, CI/deploy) and block "done" on Critical/High gaps. Use before finishing any change that touches auth, accounts, sessions, the database or migrations, API routes, anything that renders user-supplied content, uploads, env vars, deploy config, or CI; when asked to review, audit, harden, ship, deploy, or open a PR; and when scaffolding a new project. Works for FastAPI, Next.js, Express/React, static HTML/JS, and SwiftUI projects.
---

# Production Standard

This skill holds the codebase to the rules in `references/standard.md`. Each rule has an ID
(DB-1, AUTH-3, API-1, FE-1, PRIV-1, OPS-1, …), and findings must cite one.

You are a reviewer and a fixer. Students learn from the findings, so explain the *why* in a
sentence, point at the exact line, and show the fix in the codebase's own style.

## When to run

- **After any change** touching: auth/accounts/sessions, DB models or migrations, API routes,
  HTML rendering of user data, uploads, logging, env/config, deploy files, CI.
  Scope the review to the changed files and whatever they call.
- **Full audit** when asked to review, harden, or ship the whole project, or before a launch.
- **Scaffolding:** when creating a new project, start compliant (see the stack reference).

## Workflow

### 1. Detect the stack and load the matching reference

| Signal | Stack | Read |
|---|---|---|
| `pyproject.toml` with `fastapi` | FastAPI | `references/fastapi.md` |
| `package.json` with `next` | Next.js | `references/nextjs.md` |
| `package.json` with `express` | Express (+ React/Vite) | `references/express.md` |
| `*.xcodeproj`, `Package.swift`, `project.yml` | SwiftUI / iOS | `references/ios.md` |
| `.github/workflows`, `Procfile`, `railway.json`, `.railway/`, `vercel.json` | Deploy/CI | `references/deploy.md` |

Monorepos (e.g. `api/` + `app/` + `ios/`) get every applicable reference.

### 2. Run the mechanical checks

Run these from the project root. Each hit is a *candidate*, so read the surrounding code before
reporting it. Skip `node_modules`, `.venv`, `.next`, `dist`, and build output.

```bash
# FE-1 user data into HTML (vanilla JS / React)
grep -rnE "innerHTML\s*[+]?=|insertAdjacentHTML|outerHTML\s*=" --include='*.js' --include='*.ts' --include='*.tsx' . | grep -v node_modules
grep -rn "dangerouslySetInnerHTML" --include='*.tsx' --include='*.jsx' . | grep -v node_modules
# DB-1 string-built SQL
grep -rnE "(execute|text|query)\(\s*f[\"']|sql\.raw|\.query\(\s*`[^`]*\\\$\{" --include='*.py' --include='*.ts' . | grep -v node_modules
# FE-2 / DB-3 secrets in client code or the repo
grep -rnE "(sk-|sk_live|re_[A-Za-z0-9]{10,}|AIza|ghp_|PASSPHRASE|SECRET\s*=\s*['\"][^'\"]{8,})" --include='*.js' --include='*.ts' --include='*.tsx' --include='*.swift' --include='*.plist' --include='*.html' . | grep -v node_modules
grep -rn "NEXT_PUBLIC_" --include='*.ts' --include='*.tsx' . | grep -v node_modules
git ls-files | grep -E "(^|/)\.env($|\.)" | grep -v example
# API-8 PII / tokens in logs
grep -rnE "(console\.(log|info|error)|logger\.(info|warning|error)|print)\(.*(email|token|password|reset|body)" --include='*.py' --include='*.ts' . | grep -v node_modules
# FE-4 zoom lock
grep -rn "maximum-scale=1" --include='*.html' .
```

Then do the checks that need reading, not grepping:

- **API-1 (BOLA):** list every route that takes an ID (path param or body field). Confirm the
  query filters by the signed-in user, or the route requires admin. This is the #1 API risk,
  so never skip it.
- **AUTH-3:** list every route that accepts a password or sends an email (login, *bearer/token*
  login, register, forgot/reset, resend-verification). Confirm each one is in the rate-limit
  table and that the limiter keys on `X-Real-IP` (Railway) with bounded memory.
- **AUTH-2 / AUTH-8:** trace how a user becomes an admin and what an unverified account can do.
- **AUTH-5 / AUTH-6:** can the user change email or password without the current password? Can they
  delete their own account?
- **API-4:** fetch the headers (`curl -sI` against a running dev server) or read the header
  config. FastAPI: `app/security.py`. Next: `next.config.*` `headers()`. Express: `helmet`.
- **FE-3:** anything gated only in client JS (paywalls, admin toggles, credit math)?
- **PRIV-1/2/3:** what personal data is collected? Is there a privacy policy link? Are the users
  minors, or is the data health-related?

### 3. Run the project's own gates

Use whatever the project defines, and report failures verbatim:

- Python: `uv run pytest`
- Node: `npm run typecheck` (or `check`), `npm run lint`, `npm test`, `npm run build`
- Dependencies: `npm audit --audit-level=high` / `uvx pip-audit`

### 4. Report

One table, most severe first, then a one-line verdict:

```
| Rule | Sev | Where | Problem | Fix |
|------|-----|-------|---------|-----|
| AUTH-3 | High | api/app/rate_limit.py:55 | /auth/bearer/login has no limit; unlimited password guessing | add ("POST", "/api/auth/bearer/login") to _rules |

Verdict: BLOCKED. 1 High open.  (or: PASS. 0 Critical/High; 3 Medium tracked in docs/SECURITY-GAPS.md)
```

Severity follows the guide in `references/standard.md`. Don't inflate: a missing header on a
JSON-only API is Medium, not Critical. Don't deflate: an unverified email that unlocks admin
is High even if "nobody would do that".

### 5. Gate

- **Critical or High open → the task is not done.** Fix it (preferred) or stop and tell the
  user exactly what blocks shipping. Never mark work complete over an open High.
- **Medium/Low →** fix if it is in the files you touched; otherwise add or update the row in
  `docs/SECURITY-GAPS.md` (rule, severity, file:line, status `Open`).
- Every fix to auth, rate limiting, authorization, or escaping gets a test that would have caught
  the bug.

## Good patterns already in these repos (reuse them)

| Need | Reference implementation |
|---|---|
| Security headers + CORS allowlist (FastAPI) | `mindrep/app/security.py` |
| Startup config validation | `mindrep/app/config.py` (`validate_production`) |
| Owner-scoped lookup that 404s on foreign rows | `tastetrace/api/app/deps.py` |
| Generic 500 + request-id logging | `mindrep/app/logging.py` |
| Hand-written input validation (TS) | `papaspuzzles/src/lib/validate.ts` |
| Upload sniffing, safe filenames, traversal guard | `papaspuzzles/src/lib/storage.ts` |
| Transactional credit spend with row locks | `papaspuzzles/src/lib/services/redemptions.ts` |
| Hashed, single-use, expiring tokens | `papaspuzzles/src/app/api/auth/reset-password/route.ts` |
| Keychain token storage | `tastetrace/ios/.../KeychainTokenStore.swift` |

## What not to do

- Don't add a dependency when ten lines in the project's style will do.
- Don't weaken a control to make a test pass (e.g. widening CSP, disabling a rate limit in prod).
- Don't write legal text (privacy policy, consent wording). Flag PRIV gaps for the teacher.
- Don't push, deploy, or change GitHub/Railway settings. List them as owner actions.
