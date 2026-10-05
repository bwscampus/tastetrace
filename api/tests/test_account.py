"""Account-level controls from the Production Standard.

AUTH-3 rate limits (including the iOS bearer login), AUTH-5 current password
for sensitive changes, AUTH-6 self-service deletion, API-9 honest health.
"""

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.auth.models import AccessToken
from app.models import Meal
from tests.conftest_project import PASSWORD, register_and_login


async def bearer_login(client, email, password=PASSWORD, ip="198.51.100.7"):
    return await client.post(
        "/api/auth/bearer/login",
        data={"username": email, "password": password},
        headers={"X-Real-IP": ip},
    )


# ── AUTH-3 ──────────────────────────────────────────────────────────────────


async def test_bearer_login_is_rate_limited(client):
    await register_and_login(client, "ios@example.com")
    statuses = [
        (await bearer_login(client, "ios@example.com", "wrong guess")).status_code
        for _ in range(12)
    ]
    assert 429 in statuses, "the iOS login must be limited like the cookie login"


async def test_spoofed_forwarded_for_does_not_reset_the_limit(client):
    await register_and_login(client, "spoof@example.com")
    statuses = []
    for i in range(12):
        response = await client.post(
            "/api/auth/login",
            data={"username": "spoof@example.com", "password": "wrong guess"},
            headers={"X-Real-IP": "203.0.113.9", "X-Forwarded-For": f"10.0.0.{i}"},
        )
        statuses.append(response.status_code)
    assert statuses[-1] == 429, "a fresh X-Forwarded-For per request must not bypass the limit"


async def test_rate_limited_response_has_retry_after(client):
    for _ in range(12):
        response = await bearer_login(client, "nobody@example.com", "x", ip="192.0.2.50")
    assert response.status_code == 429
    assert int(response.headers["Retry-After"]) > 0


def test_rate_limiter_memory_is_bounded(monkeypatch):
    import time

    from app import rate_limit
    from app.config import settings

    monkeypatch.setattr(rate_limit, "MAX_TRACKED_KEYS", 50)
    limiter = rate_limit.RateLimitMiddleware(app=None, settings=settings)
    now = time.monotonic()
    for i in range(500):
        limiter._evict(now)
        limiter._hits[f"POST /api/auth/login 10.0.{i // 256}.{i % 256}"] = rate_limit.deque([now])
    assert len(limiter._hits) <= 50


# ── AUTH-5 ──────────────────────────────────────────────────────────────────


async def test_password_change_requires_current_password(client):
    auth = await register_and_login(client, "pw@example.com")
    response = await client.patch(
        "/api/users/me", headers=auth, json={"password": "a brand new passphrase"}
    )
    assert response.status_code == 400
    response = await client.patch(
        "/api/users/me",
        headers=auth,
        json={"password": "a brand new passphrase", "currentPassword": "wrong"},
    )
    assert response.status_code == 400


async def test_email_change_requires_current_password(client):
    auth = await register_and_login(client, "old@example.com")
    response = await client.patch("/api/users/me", headers=auth, json={"email": "new@example.com"})
    assert response.status_code == 400
    response = await client.patch(
        "/api/users/me",
        headers=auth,
        json={"email": "new@example.com", "currentPassword": PASSWORD},
    )
    assert response.status_code == 200, response.text
    assert response.json()["email"] == "new@example.com"


async def test_name_change_needs_no_password(client):
    auth = await register_and_login(client, "name@example.com")
    response = await client.patch("/api/users/me", headers=auth, json={"firstName": "Taylor"})
    assert response.status_code == 200, response.text
    assert response.json()["firstName"] == "Taylor"


async def test_password_change_signs_out_other_sessions(client):
    phone = await register_and_login(client, "multi@example.com")
    laptop_login = await bearer_login(client, "multi@example.com")
    laptop = {"Authorization": f"Bearer {laptop_login.json()['access_token']}"}

    response = await client.patch(
        "/api/users/me",
        headers=phone,
        json={"password": "a brand new passphrase", "currentPassword": PASSWORD},
    )
    assert response.status_code == 200, response.text
    assert (await client.get("/api/users/me", headers=phone)).status_code == 200
    assert (await client.get("/api/users/me", headers=laptop)).status_code == 401


# ── AUTH-6 ──────────────────────────────────────────────────────────────────


async def test_delete_account_requires_password(client):
    auth = await register_and_login(client, "keep@example.com")
    response = await client.request(
        "DELETE", "/api/users/me", headers=auth, json={"password": "wrong"}
    )
    assert response.status_code == 400
    assert (await client.get("/api/users/me", headers=auth)).status_code == 200


async def test_delete_account_removes_user_tokens_and_data(client, engine):
    auth = await register_and_login(client, "leaving@example.com")
    meal = await client.post(
        "/api/meals", headers=auth, json={"name": "Toast", "mealType": "Breakfast"}
    )
    assert meal.status_code == 201, meal.text

    response = await client.request(
        "DELETE", "/api/users/me", headers=auth, json={"password": PASSWORD}
    )
    assert response.status_code == 204, response.text
    assert (await client.get("/api/users/me", headers=auth)).status_code == 401
    assert (await bearer_login(client, "leaving@example.com", ip="198.51.100.99")).status_code == 400

    async with async_sessionmaker(engine)() as session:
        assert await session.scalar(select(func.count()).select_from(Meal)) == 0
        assert await session.scalar(select(func.count()).select_from(AccessToken)) == 0


# ── API-9 ───────────────────────────────────────────────────────────────────


async def test_health_does_not_leak_environment(client):
    body = (await client.get("/api/health")).json()
    assert body == {"status": "ok"}


async def test_health_reports_503_when_database_is_down(client):
    from app.db import get_async_session

    class DeadSession:
        async def execute(self, *_args, **_kwargs):
            raise ConnectionError("db down")

    async def dead_session():
        yield DeadSession()

    app = client._transport.app
    app.dependency_overrides[get_async_session] = dead_session
    response = await client.get("/api/health")
    assert response.status_code == 503


async def test_malformed_request_id_is_replaced(client):
    response = await client.get("/api/health", headers={"X-Request-ID": "bad\nid with spaces"})
    assert response.headers["X-Request-ID"] != "bad\nid with spaces"
    response = await client.get("/api/health", headers={"X-Request-ID": "abc-123"})
    assert response.headers["X-Request-ID"] == "abc-123"
