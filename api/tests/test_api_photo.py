"""The meal photo route: the guards, the limits, and that nothing is stored."""

import base64
import json

import pytest
from sqlalchemy import func, select

from app.ai import photo
from app.models import Meal
from app.routers import ai as ai_router
from tests.conftest_project import register_and_login

JPEG = b"\xff\xd8\xff" + b"\x00" * 64
HEIC = b"\x00\x00\x00\x18ftypheic" + b"\x00" * 64

GOOD_REPLY = {
    "recognized": True,
    "name": "Chicken burrito bowl",
    "ingredients": [
        {"name": "Chicken", "cookMethod": "grilled"},
        {"name": "black beans", "cookMethod": None},
    ],
    "mealCategory": "Lunch",
    "containsGluten": False,
    "containsDairy": True,
    "containsGrains": True,
    "containsSugar": False,
    "containsNuts": False,
    "confidence": "high",
}


class TextBlock:
    type = "text"

    def __init__(self, text: str) -> None:
        self.text = text


class FakeResponse:
    stop_reason = "end_turn"
    stop_details = None

    def __init__(self, payload) -> None:
        self.content = [TextBlock(json.dumps(payload))]


class FakeClient:
    def __init__(self, result) -> None:
        self._result = result
        self.calls: list[dict] = []

    @property
    def beta(self):
        return self

    @property
    def messages(self):
        return self

    async def create(self, **kwargs):
        self.calls.append(kwargs)
        if isinstance(self._result, Exception):
            raise self._result
        return self._result

    async def close(self):
        return None


@pytest.fixture(autouse=True)
def reset_limits():
    """Both limiters are module singletons, so they leak between tests."""
    photo.throttle.clear()
    ai_router.daily_quota.clear()
    yield
    photo.throttle.clear()
    ai_router.daily_quota.clear()


@pytest.fixture
def model_on(monkeypatch):
    monkeypatch.setattr(photo.settings, "ANTHROPIC_API_KEY", "sk-ant-test")
    monkeypatch.setattr(photo.settings, "PHOTO_RECOGNITION_ENABLED", True)

    def use(result=None) -> FakeClient:
        client = FakeClient(FakeResponse(GOOD_REPLY) if result is None else result)
        monkeypatch.setattr(photo, "_client_factory", lambda: client)
        return client

    return use


def body(raw: bytes = JPEG, **extra) -> dict:
    return {"imageBase64": base64.standard_b64encode(raw).decode(), **extra}


async def post(client, auth, **kwargs):
    return await client.post("/api/ai/meal-photo", headers=auth, json=body(**kwargs))


# ── Availability and auth ───────────────────────────────────────────────────


async def test_without_a_key_it_reports_itself_unavailable(client):
    auth = await register_and_login(client, "taylor@example.com")
    response = await post(client, auth)
    assert response.status_code == 503
    assert "Type the meal in" in response.json()["detail"]


async def test_the_flag_turns_it_off_without_removing_the_route(client, monkeypatch):
    """A 404 could not tell a shipped app "off" from "older server"."""
    monkeypatch.setattr(photo.settings, "ANTHROPIC_API_KEY", "sk-ant-test")
    monkeypatch.setattr(photo.settings, "PHOTO_RECOGNITION_ENABLED", False)
    auth = await register_and_login(client, "taylor@example.com")
    response = await post(client, auth)
    assert response.status_code == 503


async def test_it_needs_a_token(client, model_on):
    model_on()
    response = await client.post("/api/ai/meal-photo", json=body())
    assert response.status_code == 401


async def test_the_route_is_in_the_schema(client):
    document = (await client.get("/openapi.json")).json()
    assert "/api/ai/meal-photo" in document["paths"]


# ── The guards ──────────────────────────────────────────────────────────────


async def test_a_format_the_model_cannot_read_is_refused(client, model_on):
    fake = model_on()
    auth = await register_and_login(client, "taylor@example.com")
    response = await post(client, auth, raw=HEIC)
    assert response.status_code == 415
    assert "JPEG" in response.json()["detail"]
    assert fake.calls == [], "nothing should reach the model"


async def test_rubbish_base64_is_refused(client, model_on):
    model_on()
    auth = await register_and_login(client, "taylor@example.com")
    response = await client.post(
        "/api/ai/meal-photo", headers=auth, json={"imageBase64": "!!!! not base64 !!!!"}
    )
    assert response.status_code == 400


async def test_an_oversized_photo_is_refused(client, model_on, monkeypatch):
    model_on()
    monkeypatch.setattr(photo.settings, "MAX_PHOTO_BYTES", 1024)
    auth = await register_and_login(client, "taylor@example.com")
    response = await post(client, auth, raw=b"\xff\xd8\xff" + b"\x00" * 4096)
    assert response.status_code == 413


async def test_a_photo_too_big_is_refused_before_the_body_is_read(client, model_on):
    """The body-size middleware catches it from Content-Length alone.

    It never reaches pydantic's field-length check, which is the point: by the
    time a schema sees a field, the whole body has already been buffered.
    """
    model_on()
    auth = await register_and_login(client, "taylor@example.com")
    response = await client.post(
        "/api/ai/meal-photo", headers=auth, json={"imageBase64": "A" * (9 * 1024 * 1024)}
    )
    assert response.status_code == 413


# ── The limits ──────────────────────────────────────────────────────────────


async def test_a_second_read_inside_the_window_is_refused_with_a_retry_after(client, model_on):
    model_on()
    auth = await register_and_login(client, "taylor@example.com")
    assert (await post(client, auth)).status_code == 200

    second = await post(client, auth)
    assert second.status_code == 429
    assert int(second.headers["retry-after"]) > 0


async def test_the_daily_ceiling_stops_an_expensive_day(client, model_on, monkeypatch):
    model_on()
    monkeypatch.setattr(photo.settings, "PHOTO_DAILY_LIMIT", 2)
    auth = await register_and_login(client, "taylor@example.com")

    for _ in range(2):
        photo.throttle.clear()  # stand in for the window elapsing
        assert (await post(client, auth)).status_code == 200

    photo.throttle.clear()
    blocked = await post(client, auth)
    assert blocked.status_code == 429
    assert "today's limit" in blocked.json()["detail"]


async def test_a_refused_photo_does_not_spend_the_users_quota(client, model_on):
    """Being told the format is wrong must not cost a slot."""
    model_on()
    auth = await register_and_login(client, "taylor@example.com")
    assert (await post(client, auth, raw=HEIC)).status_code == 415
    # Still allowed straight away, so neither limiter was charged.
    assert (await post(client, auth)).status_code == 200


# ── The result ──────────────────────────────────────────────────────────────


async def test_a_good_read_comes_back_in_the_shape_a_meal_is_created_from(client, model_on):
    model_on()
    auth = await register_and_login(client, "taylor@example.com")
    response = await post(client, auth, kind="label", mealType="Dinner", hint="burrito")
    assert response.status_code == 200, response.text
    read = response.json()

    assert read["recognized"] is True
    assert read["name"] == "Chicken burrito bowl"
    # camelCase on the wire, and lowercased names, so the client can post it back
    assert read["ingredients"] == [
        {"name": "chicken", "cookMethod": "grilled"},
        {"name": "black beans", "cookMethod": None},
    ]
    assert read["mealCategory"] == "Lunch"
    assert read["containsDairy"] is True
    assert read["containsGluten"] is False
    assert read["confidence"] == "high"
    assert read["kind"] == "label"
    assert read["model"] == photo.settings.PHOTO_MODEL
    assert read["message"] is None


async def test_the_fields_it_returns_are_accepted_by_the_meal_endpoint(client, model_on):
    """The point of the shape: no translation layer between the two calls."""
    model_on()
    auth = await register_and_login(client, "taylor@example.com")
    read = (await post(client, auth)).json()

    created = await client.post(
        "/api/meals",
        headers=auth,
        json={
            "name": read["name"],
            "mealType": read["mealCategory"],
            "ingredientDetails": read["ingredients"],
            "containsGluten": read["containsGluten"],
            "containsDairy": read["containsDairy"],
            "containsGrains": read["containsGrains"],
            "containsSugar": read["containsSugar"],
            "containsNuts": read["containsNuts"],
            "tz": "America/Los_Angeles",
        },
    )
    assert created.status_code == 201, created.text
    assert created.json()["ingredients"] == ["chicken", "black beans"]


async def test_a_model_failure_answers_200_so_the_screen_always_has_something(client, model_on):
    model_on(RuntimeError("upstream fell over"))
    auth = await register_and_login(client, "taylor@example.com")
    response = await post(client, auth)
    assert response.status_code == 200
    read = response.json()
    assert read["recognized"] is False
    assert read["name"] == ""
    assert "Type the meal in" in read["message"]


async def test_reading_a_photo_writes_nothing(client, engine, model_on):
    model_on()
    auth = await register_and_login(client, "taylor@example.com")
    assert (await post(client, auth)).status_code == 200

    async with engine.connect() as connection:
        meals = await connection.scalar(select(func.count()).select_from(Meal.__table__))
    assert meals == 0, "the photo route must not create anything"


async def test_one_persons_photo_cannot_be_read_onto_anothers_account(client, model_on):
    """There is no id to pass, which is the point: nothing to enumerate."""
    model_on()
    auth = await register_and_login(client, "taylor@example.com")
    other = await register_and_login(client, "sam@example.com")
    assert (await post(client, auth)).status_code == 200
    # A different account has its own window, unaffected by the first.
    assert (await post(client, other)).status_code == 200
