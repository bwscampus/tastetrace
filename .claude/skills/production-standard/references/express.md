# Express (+ React/Vite) checks

## API-4: headers

```ts
import helmet from "helmet";
app.disable("x-powered-by");
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"], // Tailwind/shadcn runtime styles
      imgSrc: ["'self'", "data:", "blob:"],
      connectSrc: ["'self'"],
      frameAncestors: ["'none'"],
      objectSrc: ["'none'"],
    },
  },
}));
```
In dev, Vite's HMR needs `'unsafe-inline'`/ws, so only apply the strict CSP when
`app.get("env") === "production"`.

## AUTH-3: rate limiting

```ts
import rateLimit from "express-rate-limit";
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, limit: 10,
  standardHeaders: "draft-7", legacyHeaders: false,
  keyGenerator: (req) => (req.get("x-real-ip") ?? req.ip ?? "unknown"),
  message: { message: "Too many attempts. Please wait and try again." },
});
app.post("/api/login", authLimiter, passport.authenticate("local"), ...);
app.post("/api/register", authLimiter, ...);
```
Every credential route gets the limiter, including legacy or "mobile" token routes. Better
still, delete routes nothing calls.

## AUTH-4: sessions

`express-session` cookie: `httpOnly: true`, `secure: "auto"` with `app.set("trust proxy", 1)`,
**`sameSite: "lax"`** (don't rely on browser defaults; Safari and Firefox don't default to Lax).
Fail at startup if `SESSION_SECRET` is missing.

## API-2 / AUTH-7

- Normalize emails (`trim().toLowerCase()`) on register *and* login, and validate format.
- Same password rule on server and client (≥ 8).
- Generic messages on login failure.

## API-3

The error handler must not send `err.message` for 500s:
```ts
app.use((err, _req, res, _next) => {
  const status = err.status || err.statusCode || 500;
  if (status >= 500) console.error(err);
  res.status(status).json({ message: status >= 500 ? "Internal Server Error" : err.message });
});
```

## API-8

Request-logging middleware must not capture response bodies; they contain tokens and emails.
Log method, path, status, and duration only.

## DB-2

Drizzle: use `drizzle-kit generate` + `migrate` with committed migration files. `drizzle-kit push`
against production can drop or rename columns silently.

## FE-6

Forms show success only on `res.ok`. `fetch` does not reject on 4xx or 5xx.
