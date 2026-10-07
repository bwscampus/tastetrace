"""The landing page's signup form: the only unauthenticated write in the API.

Ported from the Express backend being retired, so these tests also pin the
behaviour that came with it — the honeypot, the idempotent insert, and the one
reply that does not reveal whether an address is already enrolled.
"""

from sqlalchemy import func, select

from app.config import settings
from app.models import WaitlistSignup

LANDING = "https://tastetrace.app"
JOINED = "You're on the list"


async def _emails(engine) -> list[str]:
    async with engine.connect() as connection:
        rows = await connection.execute(select(WaitlistSignup.email).order_by(WaitlistSignup.id))
        return [row[0] for row in rows]


async def _count(engine) -> int:
    async with engine.connect() as connection:
        return await connection.scalar(select(func.count()).select_from(WaitlistSignup.__table__))


async def test_a_signup_is_stored_and_needs_no_account(client, engine):
    response = await client.post("/api/waitlist", json={"email": "Reader@Example.com"})
    assert response.status_code == 201, response.text
    assert response.json()["message"] == JOINED
    # Lowercased on the way in, so the unique constraint actually means something
    assert await _emails(engine) == ["reader@example.com"]


async def test_signing_up_twice_is_not_an_error_and_not_a_duplicate(client, engine):
    first = await client.post("/api/waitlist", json={"email": "reader@example.com"})
    second = await client.post("/api/waitlist", json={"email": "reader@example.com"})

    assert first.status_code == 201
    assert second.status_code == 201
    # The same reply either way: "already on the list" would let anyone test
    # whether a given address had signed up.
    assert second.json()["message"] == first.json()["message"]
    assert await _count(engine) == 1


async def test_the_honeypot_stores_nothing_but_says_it_worked(client, engine):
    response = await client.post(
        "/api/waitlist", json={"email": "bot@example.com", "company": "Acme"}
    )
    assert response.status_code == 201
    assert response.json()["message"] == JOINED, "a bot must get no signal"
    assert await _count(engine) == 0


async def test_an_invalid_address_is_refused(client, engine):
    for bad in ["not-an-email", "", "a@", "@b.co", "a b@example.com"]:
        response = await client.post("/api/waitlist", json={"email": bad})
        assert response.status_code == 422, f"{bad!r} should not be accepted"
    assert await _count(engine) == 0


async def test_an_absurdly_long_address_is_refused(client):
    response = await client.post(
        "/api/waitlist", json={"email": "a" * 250 + "@example.com"}
    )
    assert response.status_code == 422


# ── CORS, which this route answers for itself ───────────────────────────────


async def test_the_landing_page_origin_is_allowed(client):
    response = await client.post(
        "/api/waitlist", json={"email": "reader@example.com"}, headers={"Origin": LANDING}
    )
    assert response.status_code == 201
    assert response.headers["access-control-allow-origin"] == LANDING
    # Without Vary a cache could hand one origin's response to another
    assert response.headers["vary"] == "Origin"


async def test_a_foreign_origin_gets_no_cors_header(client):
    response = await client.post(
        "/api/waitlist",
        json={"email": "reader@example.com"},
        headers={"Origin": "https://evil.example.com"},
    )
    # The write still happens — CORS is a browser rule, not a server one — but
    # the browser will not let the attacker's page read the reply.
    assert response.status_code == 201
    assert "access-control-allow-origin" not in response.headers


async def test_the_preflight_is_answered_for_an_allowed_origin(client):
    response = await client.request(
        "OPTIONS",
        "/api/waitlist",
        headers={
            "Origin": LANDING,
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "Content-Type",
        },
    )
    assert response.status_code == 204
    assert response.headers["access-control-allow-origin"] == LANDING
    assert "POST" in response.headers["access-control-allow-methods"]


async def test_every_landing_origin_is_allowed_by_default():
    assert "https://tastetrace.app" in settings.WAITLIST_ORIGINS
    assert "https://www.tastetrace.app" in settings.WAITLIST_ORIGINS


async def test_the_api_still_installs_no_shared_cors(client):
    """The shared CORS middleware would enable credentials on every route.

    This route carries its own headers precisely so that does not happen for the
    sake of one public form.
    """
    assert not settings.ALLOWED_ORIGINS
    response = await client.get("/api/health", headers={"Origin": LANDING})
    assert "access-control-allow-origin" not in response.headers


# ── The body cap, which applies to every route ──────────────────────────────


async def test_an_oversized_body_is_refused_before_it_is_read(client):
    response = await client.post(
        "/api/waitlist",
        json={"email": "reader@example.com", "company": "x" * (settings.MAX_REQUEST_BYTES + 1000)},
    )
    assert response.status_code == 413
    assert "too large" in response.json()["detail"]


async def test_an_ordinary_body_is_unaffected(client):
    response = await client.post("/api/waitlist", json={"email": "reader@example.com"})
    assert response.status_code == 201


async def test_the_whole_address_is_lowercased_not_just_the_domain(client, engine):
    """Mixed case in the local part must not create a second row.

    pydantic's EmailStr lowercases only the domain, so without the explicit
    normalisation Reader@example.com and reader@example.com would both be
    stored and the unique constraint would mean nothing.
    """
    await client.post("/api/waitlist", json={"email": "Reader@Example.com"})
    await client.post("/api/waitlist", json={"email": "reader@example.com"})
    await client.post("/api/waitlist", json={"email": "  READER@EXAMPLE.COM  "})
    assert await _emails(engine) == ["reader@example.com"]
