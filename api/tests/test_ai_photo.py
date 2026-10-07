"""Reading a meal photo: the guards, the mapping, and the model call.

The route is covered in test_api_photo.py; this file is the module on its own.
"""

import base64
import json

import anthropic
import httpx
import pytest

from app.ai import photo
from app.domain.cook_methods import COOK_METHODS

JPEG = b"\xff\xd8\xff" + b"\x00" * 40
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 40
WEBP = b"RIFF" + b"\x00\x00\x00\x00" + b"WEBP" + b"\x00" * 30
GIF = b"GIF89a" + b"\x00" * 40
# What an iPhone actually produces by default, and what the API rejects.
HEIC = b"\x00\x00\x00\x18ftypheic" + b"\x00" * 40
PDF = b"%PDF-1.7" + b"\x00" * 40


def b64(raw: bytes) -> str:
    return base64.standard_b64encode(raw).decode()


# ── The guards ──────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "raw,expected",
    [(JPEG, "image/jpeg"), (PNG, "image/png"), (WEBP, "image/webp"), (GIF, "image/gif")],
    ids=["jpeg", "png", "webp", "gif"],
)
def test_the_media_type_comes_from_the_bytes(raw, expected):
    decoded, media_type = photo.decode_image(b64(raw))
    assert decoded == raw
    assert media_type == expected


@pytest.mark.parametrize("raw", [HEIC, PDF], ids=["heic", "pdf"])
def test_formats_the_model_cannot_read_are_refused_by_name(raw):
    with pytest.raises(photo.PhotoRejected) as caught:
        photo.decode_image(b64(raw))
    assert caught.value.status_code == 415
    # The message names JPEG because HEIC is the common case and the fix is
    # always "re-encode", never "try again".
    assert "JPEG" in caught.value.detail


def test_a_claimed_type_is_never_believed_over_the_bytes():
    """A PDF renamed as a JPEG must not be forwarded to the model."""
    with pytest.raises(photo.PhotoRejected) as caught:
        photo.decode_image(b64(PDF))
    assert caught.value.status_code == 415


def test_rubbish_base64_is_refused():
    with pytest.raises(photo.PhotoRejected) as caught:
        photo.decode_image("this is not base64 at all !!!")
    assert caught.value.status_code == 400


def test_an_empty_image_is_refused():
    with pytest.raises(photo.PhotoRejected) as caught:
        photo.decode_image("")
    assert caught.value.status_code == 400


def test_an_oversized_photo_is_refused_before_the_model(monkeypatch):
    monkeypatch.setattr(photo.settings, "MAX_PHOTO_BYTES", 1024)
    with pytest.raises(photo.PhotoRejected) as caught:
        photo.decode_image(b64(b"\xff\xd8\xff" + b"\x00" * 2048))
    assert caught.value.status_code == 413
    assert "larger than" in caught.value.detail


# ── The schema ──────────────────────────────────────────────────────────────


def test_the_schema_only_allows_cook_methods_the_analytics_know():
    schema = photo.response_schema()
    allowed = schema["properties"]["ingredients"]["items"]["properties"]["cookMethod"]["enum"]
    assert set(allowed) == {*COOK_METHODS, None}
    assert "air-fried" not in allowed


def test_the_schema_is_closed_and_fully_required():
    schema = photo.response_schema()
    assert schema["additionalProperties"] is False
    assert set(schema["required"]) == set(schema["properties"])
    assert schema["properties"]["ingredients"]["items"]["additionalProperties"] is False


# ── The mapping ─────────────────────────────────────────────────────────────


def _payload(**overrides) -> dict:
    base = {
        "recognized": True,
        "name": "Chicken burrito bowl",
        "ingredients": [{"name": "chicken", "cookMethod": "grilled"}],
        "mealCategory": "Lunch",
        "containsGluten": False,
        "containsDairy": True,
        "containsGrains": True,
        "containsSugar": False,
        "containsNuts": False,
        "confidence": "high",
    }
    return {**base, **overrides}


def test_a_good_reply_maps_onto_the_meal_fields():
    result = photo.recognition_from_model(_payload(), "claude-opus-5-5")
    assert result.recognized
    assert result.name == "Chicken burrito bowl"
    assert result.ingredients == [{"name": "chicken", "cook_method": "grilled"}]
    assert result.meal_category == "Lunch"
    assert result.contains_dairy and result.contains_grains
    assert not result.contains_gluten
    assert result.confidence == "high"
    assert result.model == "claude-opus-5-5"


def test_an_unknown_cook_method_is_dropped_rather_than_echoed():
    """A style the correlation engine never matches is worse than none."""
    result = photo.recognition_from_model(
        _payload(ingredients=[{"name": "tofu", "cookMethod": "air-fried"}]), "m"
    )
    assert result.ingredients == [{"name": "tofu", "cook_method": None}]


def test_ingredient_names_are_normalised_the_way_the_watchlist_compares_them():
    result = photo.recognition_from_model(
        _payload(ingredients=[{"name": "  Sourdough Bread  ", "cookMethod": None}]), "m"
    )
    assert result.ingredients == [{"name": "sourdough bread", "cook_method": None}]


def test_blank_and_duplicate_ingredients_are_dropped():
    result = photo.recognition_from_model(
        _payload(
            ingredients=[
                {"name": "egg", "cookMethod": None},
                {"name": "   ", "cookMethod": None},
                {"name": "EGG", "cookMethod": None},
            ]
        ),
        "m",
    )
    assert result.ingredients == [{"name": "egg", "cook_method": None}]


def test_a_long_list_is_truncated_to_what_a_meal_accepts():
    many = [{"name": f"item {i}", "cookMethod": None} for i in range(200)]
    result = photo.recognition_from_model(_payload(ingredients=many), "m")
    assert len(result.ingredients) == photo.MAX_INGREDIENTS


def test_an_invented_meal_category_or_confidence_falls_back():
    result = photo.recognition_from_model(
        _payload(mealCategory="Brunch", confidence="certain"), "m"
    )
    assert result.meal_category is None
    assert result.confidence == "low"


@pytest.mark.parametrize(
    "overrides",
    [{"recognized": False}, {"name": ""}, {"name": "   "}],
    ids=["model-said-no", "empty-name", "blank-name"],
)
def test_an_unrecognised_photo_carries_the_type_it_in_message(overrides):
    result = photo.recognition_from_model(_payload(**overrides), "m")
    assert not result.recognized
    assert result.name == ""
    assert result.ingredients == []
    assert result.message == photo.CANNOT_READ


def test_a_reply_missing_fields_entirely_does_not_raise():
    result = photo.recognition_from_model({}, "m")
    assert not result.recognized
    assert result.message == photo.CANNOT_READ


# ── The model call ──────────────────────────────────────────────────────────


class TextBlock:
    type = "text"

    def __init__(self, text: str) -> None:
        self.text = text


class FakeResponse:
    def __init__(self, payload, stop_reason="end_turn"):
        body = payload if isinstance(payload, str) else json.dumps(payload)
        self._blocks = [TextBlock(body)]
        self.stop_reason = stop_reason
        self.stop_details = None

    @property
    def content(self):
        return self._blocks


class RefusedResponse:
    stop_reason = "refusal"

    class stop_details:  # noqa: N801 - mimicking SDK attribute access
        category = "general_harms"

    @property
    def content(self):
        raise AssertionError("content must not be read when the model refused")


class TruncatedResponse:
    stop_reason = "max_tokens"
    stop_details = None

    @property
    def content(self):
        return [TextBlock('{"recognized": true, "name": "Chick')]


class FakeClient:
    def __init__(self, result):
        self._result = result
        self.calls: list[dict] = []
        self.closed = False

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
        self.closed = True


@pytest.fixture
def fake_model(monkeypatch):
    monkeypatch.setattr(photo.settings, "ANTHROPIC_API_KEY", "sk-ant-test")

    def use(result) -> FakeClient:
        client = FakeClient(result)
        monkeypatch.setattr(photo, "_client_factory", lambda: client)
        return client

    return use


async def test_the_image_is_sent_before_the_text_with_the_sniffed_type(fake_model):
    fake = fake_model(FakeResponse(_payload()))
    result = await photo.read_photo(JPEG, "image/jpeg", kind="label", meal_type="Lunch", hint="pasta")
    assert result.recognized

    blocks = fake.calls[0]["messages"][0]["content"]
    assert [block["type"] for block in blocks] == ["image", "text"]
    assert blocks[0]["source"]["media_type"] == "image/jpeg"
    assert base64.standard_b64decode(blocks[0]["source"]["data"]) == JPEG
    context = json.loads(blocks[1]["text"])
    assert context == {"kind": "label", "mealType": "Lunch", "hint": "pasta"}


async def test_the_call_parameters_are_current(fake_model):
    fake = fake_model(FakeResponse(_payload()))
    await photo.read_photo(JPEG, "image/jpeg")

    sent = fake.calls[0]
    assert sent["model"] == "claude-opus-5-5"
    assert sent["output_config"]["effort"] == "low"
    assert sent["output_config"]["format"]["type"] == "json_schema"
    assert sent["betas"] == ["server-side-fallback-2026-07-01"]
    assert sent["fallbacks"] == "default"
    # Each of these is a 400 on this model.
    assert "thinking" not in sent
    assert "budget_tokens" not in sent
    assert "tool_choice" not in sent


async def test_a_refusal_degrades_without_reading_the_response(fake_model):
    fake_model(RefusedResponse())
    result = await photo.read_photo(JPEG, "image/jpeg")
    assert not result.recognized
    assert result.message == photo.CANNOT_READ


async def test_truncated_json_degrades_rather_than_raising(fake_model):
    fake_model(TruncatedResponse())
    result = await photo.read_photo(JPEG, "image/jpeg")
    assert not result.recognized
    assert result.message == photo.CANNOT_READ


@pytest.mark.parametrize(
    "body", ["not json at all", "[1, 2, 3]"], ids=["not-json", "json-but-not-an-object"]
)
async def test_a_reply_that_is_not_an_object_degrades(fake_model, body):
    fake_model(FakeResponse(body))
    result = await photo.read_photo(JPEG, "image/jpeg")
    assert not result.recognized
    assert result.message == photo.CANNOT_READ


@pytest.mark.parametrize(
    "error",
    [
        anthropic.APITimeoutError(request=httpx.Request("POST", "http://x")),
        anthropic.APIConnectionError(request=httpx.Request("POST", "http://x")),
        anthropic.APIStatusError(
            "boom",
            response=httpx.Response(500, request=httpx.Request("POST", "http://x")),
            body=None,
        ),
        RuntimeError("something nobody predicted"),
    ],
    ids=["timeout", "connection", "status", "unexpected"],
)
async def test_every_failure_degrades_and_closes_the_client(fake_model, error):
    fake = fake_model(error)
    result = await photo.read_photo(JPEG, "image/jpeg")
    assert not result.recognized
    assert result.message == photo.CANNOT_READ
    assert fake.closed


async def test_the_client_is_closed_on_the_happy_path_too(fake_model):
    fake = fake_model(FakeResponse(_payload()))
    await photo.read_photo(JPEG, "image/jpeg")
    assert fake.closed


async def test_without_a_key_no_client_is_built(monkeypatch):
    monkeypatch.setattr(photo.settings, "ANTHROPIC_API_KEY", None)

    def explode():
        raise AssertionError("no client should be built without a key")

    monkeypatch.setattr(photo, "_client_factory", explode)
    result = await photo.read_photo(JPEG, "image/jpeg")
    assert not result.recognized
    assert result.message == photo.UNAVAILABLE
