"""The model call behind the digest summary.

Nothing covered `_ask_claude` before this file: not the refusal branch, not the
error branches, not the path that stores the model's prose. All of it is reached
here through `_client_factory`, which exists so a fake can be injected without
monkeypatching the SDK's import site.
"""

import anthropic
import httpx
import pytest
from sqlalchemy import func, select

from app.ai import synthesis
from app.models import AiSynthesis
from tests.conftest_project import register_and_login
from tests.test_api_analytics import seed_week

TZ = "America/Los_Angeles"
WEEK = "2026-09-11"


class TextBlock:
    type = "text"

    def __init__(self, text: str) -> None:
        self.text = text


class ThinkingBlock:
    """Empty by default on current models; the prose must be picked out around it."""

    type = "thinking"
    thinking = ""


class FakeResponse:
    def __init__(self, text="A short paragraph about sourdough bread.", stop_reason="end_turn"):
        self._blocks = [ThinkingBlock(), TextBlock(text)]
        self.stop_reason = stop_reason
        self.stop_details = None

    @property
    def content(self):
        return self._blocks


class RefusedResponse:
    """Reading content on a refusal is the bug this shape catches."""

    stop_reason = "refusal"

    class stop_details:  # noqa: N801 - mimicking the SDK's attribute access
        category = "general_harms"

    @property
    def content(self):
        raise AssertionError("content must not be read when the model refused")


class TruncatedResponse:
    stop_reason = "max_tokens"
    stop_details = None

    @property
    def content(self):
        return [TextBlock("Half a sent")]


class FakeClient:
    """Mimics the slice of the SDK that synthesis.py actually touches."""

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
    """Installs a fake client and a key, and returns a setter for the result."""
    monkeypatch.setattr(synthesis.settings, "ANTHROPIC_API_KEY", "sk-ant-test")
    synthesis.throttle.clear()
    holder: dict[str, FakeClient] = {}

    def use(result) -> FakeClient:
        client = FakeClient(result)
        holder["client"] = client
        monkeypatch.setattr(synthesis, "_client_factory", lambda: client)
        return client

    yield use
    synthesis.throttle.clear()


async def _ask(client, auth, week=WEEK):
    response = await client.post(
        "/api/ai/synthesis", headers=auth, json={"weekStart": week, "tz": TZ}
    )
    assert response.status_code == 200, response.text
    return response.json()


async def _stored_rows(engine) -> int:
    async with engine.connect() as connection:
        return await connection.scalar(select(func.count()).select_from(AiSynthesis.__table__))


async def test_the_model_writes_the_summary_and_it_is_cached_afterwards(client, engine, fake_model):
    auth = await register_and_login(client, "taylor@example.com")
    await seed_week(client, auth)
    fake = fake_model(FakeResponse())

    first = await _ask(client, auth)
    assert first["source"] == "claude"
    assert first["model"] == synthesis.settings.SYNTHESIS_MODEL
    assert first["cached"] is False
    assert first["text"] == "A short paragraph about sourdough bread."
    assert fake.closed, "the client must be closed even on the happy path"

    second = await _ask(client, auth)
    assert second["cached"] is True
    assert second["text"] == first["text"]
    assert len(fake.calls) == 1, "a cache hit must not reach the model"


async def test_the_call_parameters_are_current(client, fake_model):
    """Guards the parameters that would otherwise 400, or silently cost more."""
    auth = await register_and_login(client, "taylor@example.com")
    await seed_week(client, auth)
    fake = fake_model(FakeResponse())
    await _ask(client, auth)

    sent = fake.calls[0]
    assert sent["model"] == "claude-opus-5-5"
    # Effort is pinned because this model defaults to medium, not high.
    assert sent["output_config"] == {"effort": "low"}
    # The scalar fallback form must pair with the 07-01 header; crossing them 400s.
    assert sent["betas"] == ["server-side-fallback-2026-07-01"]
    assert sent["fallbacks"] == "default"
    # All four of these are 400s on this model.
    assert "thinking" not in sent
    assert "budget_tokens" not in sent
    assert "tool_choice" not in sent
    assert sent["messages"][-1]["role"] == "user"


async def test_a_failed_call_is_not_cached_and_is_retried_once_the_model_works(
    client, engine, fake_model
):
    """The defect: a template stored under the live hash pinned it for the week.

    Before the fix the second request below returned the template with
    cached=true, and the model was never asked again until the numbers changed —
    so adding an API key appeared to do nothing.
    """
    auth = await register_and_login(client, "taylor@example.com")
    await seed_week(client, auth)

    fake_model(anthropic.APITimeoutError(request=httpx.Request("POST", "http://x")))
    failed = await _ask(client, auth)
    assert failed["source"] == "rules"
    assert failed["cached"] is False
    assert await _stored_rows(engine) == 0, "a template must never be written to the cache"

    synthesis.throttle.clear()  # stand in for the window elapsing
    fake_model(FakeResponse())
    recovered = await _ask(client, auth)
    assert recovered["source"] == "claude"
    assert await _stored_rows(engine) == 1


async def test_a_refusal_degrades_without_reading_the_response(client, engine, fake_model):
    auth = await register_and_login(client, "taylor@example.com")
    await seed_week(client, auth)
    fake_model(RefusedResponse())

    body = await _ask(client, auth)
    assert body["source"] == "rules"
    assert body["model"] is None
    assert await _stored_rows(engine) == 0


async def test_truncated_output_is_discarded_rather_than_shown(client, engine, fake_model):
    auth = await register_and_login(client, "taylor@example.com")
    await seed_week(client, auth)
    fake_model(TruncatedResponse())

    body = await _ask(client, auth)
    assert body["source"] == "rules"
    assert "Half a sent" not in body["text"]
    assert await _stored_rows(engine) == 0


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
async def test_every_failure_degrades_to_the_template(client, fake_model, error):
    auth = await register_and_login(client, "taylor@example.com")
    await seed_week(client, auth)
    fake = fake_model(error)

    body = await _ask(client, auth)
    assert body["source"] == "rules"
    assert len(body["text"]) > 20
    assert fake.closed, "the client must be closed on every error path"


async def test_without_a_key_the_model_is_never_constructed(client, monkeypatch):
    auth = await register_and_login(client, "taylor@example.com")
    await seed_week(client, auth)
    monkeypatch.setattr(synthesis.settings, "ANTHROPIC_API_KEY", None)

    def explode():
        raise AssertionError("no client should be built without a key")

    monkeypatch.setattr(synthesis, "_client_factory", explode)
    body = await _ask(client, auth)
    assert body["source"] == "rules"


async def test_the_throttle_keeps_a_second_view_off_the_model(client, fake_model):
    auth = await register_and_login(client, "taylor@example.com")
    await seed_week(client, auth)
    fake = fake_model(anthropic.APITimeoutError(request=httpx.Request("POST", "http://x")))

    await _ask(client, auth)
    await _ask(client, auth)
    assert len(fake.calls) == 1, "the window must hold after a failure, not invite a retry storm"
