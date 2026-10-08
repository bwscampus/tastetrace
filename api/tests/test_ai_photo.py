"""Reading a meal photo: the guards, the mapping, and the model call.

The route is covered in test_api_photo.py; this file is the module on its own.
"""

import base64
import json

import httpx
import openai
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
    result = photo.recognition_from_model(_payload(), "gpt-6-astra")
    assert result.recognized
    assert result.name == "Chicken burrito bowl"
    assert result.ingredients == [{"name": "chicken", "cook_method": "grilled"}]
    assert result.meal_category == "Lunch"
    assert result.contains_dairy and result.contains_grains
    assert not result.contains_gluten
    assert result.confidence == "high"
    assert result.model == "gpt-6-astra"


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


class RefusalPart:
    type = "refusal"
    refusal = "I can't help with that."


class TextPart:
    type = "output_text"


class Message:
    type = "message"

    def __init__(self, content):
        self.content = content


class FakeResponse:
    """The slice of a Responses API result that photo.py reads."""

    def __init__(self, payload, status="completed"):
        self.output_text = payload if isinstance(payload, str) else json.dumps(payload)
        self.status = status
        self.incomplete_details = None
        self.output = [Message([TextPart()])]


class RefusedResponse:
    status = "completed"
    incomplete_details = None

    def __init__(self):
        self.output = [Message([RefusalPart()])]

    @property
    def output_text(self):
        raise AssertionError("output_text must not be read when the model refused")


class TruncatedResponse:
    """Structured output cut mid-object; parsing it would raise."""

    status = "incomplete"
    output = []

    class incomplete_details:  # noqa: N801 - mimicking SDK attribute access
        reason = "max_output_tokens"

    @property
    def output_text(self):
        return '{"recognized": true, "name": "Chick'


class FakeClient:
    def __init__(self, result):
        self._result = result
        self.calls: list[dict] = []
        self.closed = False

    @property
    def responses(self):
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
    monkeypatch.setattr(photo.settings, "OPENAI_API_KEY", "sk-test")

    def use(result) -> FakeClient:
        client = FakeClient(result)
        monkeypatch.setattr(photo, "_client_factory", lambda: client)
        return client

    return use


async def test_the_image_is_sent_before_the_text_with_the_sniffed_type(fake_model):
    fake = fake_model(FakeResponse(_payload()))
    result = await photo.read_photo(JPEG, "image/jpeg", kind="label", meal_type="Lunch", hint="pasta")
    assert result.recognized

    blocks = fake.calls[0]["input"][0]["content"]
    assert [block["type"] for block in blocks] == ["input_image", "input_text"]
    # A data URL whose media type came from the sniff, not from the caller
    prefix, _, data = blocks[0]["image_url"].partition(",")
    assert prefix == "data:image/jpeg;base64"
    assert base64.standard_b64decode(data) == JPEG
    context = json.loads(blocks[1]["text"])
    assert context == {"kind": "label", "mealType": "Lunch", "hint": "pasta"}


async def test_the_call_parameters_are_current(fake_model):
    fake = fake_model(FakeResponse(_payload()))
    await photo.read_photo(JPEG, "image/jpeg")

    sent = fake.calls[0]
    assert sent["model"] == "gpt-6-astra"
    assert sent["reasoning"] == {"effort": "low"}
    fmt = sent["text"]["format"]
    assert fmt["type"] == "json_schema"
    assert fmt["name"]  # required by the API
    # Without strict the schema is a hint rather than a guarantee
    assert fmt["strict"] is True
    assert fmt["schema"] == photo.response_schema()
    assert sent["instructions"].startswith("You read one photo")


async def test_a_refusal_degrades_without_reading_the_response(fake_model):
    fake_model(RefusedResponse())
    result = await photo.read_photo(JPEG, "image/jpeg")
    assert not result.recognized
    assert result.message == photo.CANNOT_READ


async def test_an_incomplete_response_degrades_rather_than_raising(fake_model):
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
        openai.APITimeoutError(request=httpx.Request("POST", "http://x")),
        openai.APIConnectionError(request=httpx.Request("POST", "http://x")),
        openai.APIStatusError(
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
    monkeypatch.setattr(photo.settings, "OPENAI_API_KEY", None)

    def explode():
        raise AssertionError("no client should be built without a key")

    monkeypatch.setattr(photo, "_client_factory", explode)
    result = await photo.read_photo(JPEG, "image/jpeg")
    assert not result.recognized
    assert result.message == photo.UNAVAILABLE
