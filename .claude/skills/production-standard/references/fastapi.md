# FastAPI checks

Most class FastAPI apps come from the `fastapi-backend` template (fastapi-users, cookie
sessions in Postgres, `app/security.py`, `app/rate_limit.py`). That template gets a lot right.
These are the places it is easy to regress or where older copies have gaps.

## AUTH-3: rate limiting

`app/rate_limit.py` must:

1. **Key on `X-Real-IP`**, which Railway's edge overwrites on every request. Do not use the first
   `X-Forwarded-For` entry; that convention breaks the moment the app sits behind any
   other proxy.
   ```python
   def client_ip(request: Request) -> str:
       real_ip = request.headers.get("X-Real-IP")
       if real_ip:
           return real_ip.strip()
       return request.client.host if request.client else "unknown"
   ```
2. **List every credential route**, including the bearer backend if one is mounted:
   `/api/auth/login`, `/api/auth/bearer/login`, `/api/auth/register`,
   `/api/auth/forgot-password`, `/api/auth/reset-password`, plus `DELETE /api/users/me` and
   `PATCH /api/users/me` (they take a password).
3. **Bound its memory:** drop a key once its deque is empty, and cap total keys (clear the
   oldest when over the cap). An unbounded `defaultdict(deque)` is a memory-exhaustion bug.
4. Return **429** with `Retry-After`.

Test: same `X-Real-IP` → 429 after N; a rotating `X-Forwarded-For` with a fixed `X-Real-IP`
still 429s.

## AUTH-5 / AUTH-6: account changes and deletion

fastapi-users' `PATCH /users/me` changes email or password with only the session cookie. Fix:

- Subclass `UserUpdate` with `current_password: str | None`. In the router (or
  `UserManager.update`), when `email` or `password` is present, verify `current_password` with
  `user_manager.password_helper.verify_and_update`; respond 400 `UPDATE_USER_INVALID_PASSWORD`
  if it is wrong or missing.
- After a password change, delete the user's other `access_tokens` rows (same logic as
  `on_after_reset_password`).
- `DELETE /api/users/me` with body `{"password": "..."}`: verify, `user_manager.delete(user)`,
  clear the auth cookie, 204. Foreign keys must be `ondelete="CASCADE"` so user data goes too.
  The built-in `DELETE /users/{id}` is superuser-only and does **not** satisfy AUTH-6.

## API-1: ownership

Every query on user data filters by `user.id` from `current_active_user`. Pattern: a dependency
that loads a row and raises 404 if `row.user_id != user.id` (see `tastetrace/api/app/deps.py`).
Flag any `session.get(Model, id)` on user-owned models without that check.
Also check IDs inside request bodies (e.g. `dish_id` on a meal) that point at other tables.

## API-2: input size

- Every `str` field in a Pydantic schema has `max_length`; every `list` has `max_length`.
- `dict[str, Any]` bodies (JSON blobs) need a size cap, either via a validator that checks
  `len(json.dumps(v))` or a request-size middleware.

## API-9: health

```python
@router.get("/health")
async def health(session: AsyncSession = Depends(get_async_session)):
    try:
        await session.execute(text("SELECT 1"))
    except Exception:
        raise HTTPException(503, "database unavailable")
    return {"status": "ok"}
```
Don't return `environment`, versions, or hostnames.

## API-8: logging

- `email/resend_client.py`: log the user ID or a message ID, not the recipient address.
- `logging.py`: only accept a client `X-Request-ID` if it matches `^[A-Za-z0-9-]{1,64}$`;
  otherwise generate one.

## Things the template already does (verify they're still there)

- `app/security.py`: CSP `script-src 'self'`, `frame-ancestors 'none'`, nosniff, Referrer-Policy,
  HSTS in prod, CORS allowlist off by default. (API-4, API-5)
- `app/config.py`: refuses to boot in prod with a placeholder secret, `ALLOWED_HOSTS=*`, or an
  http base URL. (API-10) Also check that the email key isn't a known placeholder (`re_PLACEHOLDER`).
- Docs/OpenAPI hidden in prod; generic 500 with request ID. (API-3)
- Argon2 via pwdlib. (AUTH-1)
- `uv.lock` committed. (OPS-2)

## Tests

Use the template's `tests/conftest.py` client fixture (in-memory SQLite). Add a test for every
fix to rate limiting, ownership, and account changes. Also add a CI job that runs
`alembic upgrade head` against real Postgres, because SQLite hides JSONB and constraint
differences.
