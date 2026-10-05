# Next.js checks (App Router)

## API-4: security headers

`next.config.*` must set headers and hide the framework:

```js
const securityHeaders = [
    { key: 'Content-Security-Policy', value: [
        "default-src 'self'",
        "script-src 'self' 'unsafe-inline'",   // Next injects inline bootstrap scripts; use a nonce via middleware to drop this
        "style-src 'self' 'unsafe-inline'",
        "img-src 'self' data: blob:",           // add your image hosts
        "font-src 'self'",
        "connect-src 'self'",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "form-action 'self'",
        "object-src 'none'",
    ].join('; ') },
    { key: 'Strict-Transport-Security', value: 'max-age=15552000; includeSubDomains' },
    { key: 'X-Frame-Options', value: 'DENY' },
    { key: 'X-Content-Type-Options', value: 'nosniff' },
    { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
    { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
];
export default {
    poweredByHeader: false,
    async headers() { return [{ source: '/:path*', headers: securityHeaders }]; },
};
```

In development, Next needs `'unsafe-eval'` for React Refresh; add it only when
`process.env.NODE_ENV !== 'production'`. Run `npm run build && npm start` and check that the
browser console shows no CSP violations before you ship.

## API-1 / AUTH-8: route handlers

- Every `src/app/api/**/route.ts` handler that is not public starts with a session check
  (`requireUser()` / `requireAdmin()`).
- Identity comes from the session, never from the body or query (`email`, `userId`).
- Admin = verified identity + allowlist. An allowlist of emails (`ADMIN_EMAILS`) is only safe if
  the email is **verified** (AUTH-2).
- Server Actions are public POST endpoints: check auth inside every one.

## AUTH-2: email verification

Pattern (mirrors the password-reset token flow):
- `users.email_verified_at timestamptz null`
- `email_verification_tokens(token_hash, user_id, expires_at, used_at)`: store only SHA-256 of
  a 32-byte random token; single-use; 24h expiry.
- Signup sends the link; `POST /api/auth/verify-email` consumes it; `POST
  /api/auth/resend-verification` is rate-limited.
- Gate credit spending, history, and admin on `email_verified_at`.

## AUTH-3: rate limiting

- `clientIp()` prefers `x-real-ip` (Railway overwrites it), then falls back.
- Limited responses are **429**, not 400.
- An in-memory `Map` limiter resets on deploy and doesn't share across replicas; that's fine for one
  instance, but note it. Use Redis or Upstash when you scale out.

## FE-1 / FE-2

- `dangerouslySetInnerHTML` only with constants or sanitized HTML.
- `NEXT_PUBLIC_*` values ship to every browser, so never put a secret in one.
- `process.env.X` inside a `'use client'` file is either undefined or public.

## API-8

Never log email bodies, reset/verification links, or tokens. If the email provider key is
missing in production, fail loudly at startup instead of logging the email.

## DB-4

`ssl: { rejectUnauthorized: false }` disables certificate checks. On Railway, use the private
`*.railway.internal` `DATABASE_URL` (no TLS needed inside the private network). Otherwise
verify the certificate.

## Tests

Unit-test pure helpers (validators, `toUser`, token hashing, `clientIp`) with vitest. For route
handlers, add DB-backed integration tests against a `TEST_DATABASE_URL` when you can.
