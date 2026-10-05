"""Security hardening round 1: CSV formula injection and the AI throttle's memory."""

import uuid

from app.ai import synthesis
from app.services.export import csv_cell


def test_csv_cells_that_would_run_as_formulas_are_neutralised():
    for payload in ("=HYPERLINK(\"http://evil\")", "+1+1", "-2+3", "@SUM(A1)", "\tx", "\rx"):
        assert csv_cell(payload).lstrip('"').startswith("'"), payload
    # Ordinary text and real numbers are untouched; negative numbers stay numbers.
    assert csv_cell("Pizza") == "Pizza"
    assert csv_cell(-3) == "-3"
    assert csv_cell(2) == "2"
    # Neutralised cells are still quoted when they contain a comma.
    assert csv_cell("=1,2") == "\"'=1,2\""


def test_ai_throttle_blocks_a_second_call_within_the_window(monkeypatch):
    monkeypatch.setattr(synthesis, "_last_generated", {})
    monkeypatch.setattr(synthesis.settings, "SYNTHESIS_RATE_LIMIT_SECONDS", 30)
    user = uuid.uuid4()
    assert not synthesis._is_throttled(user, 1000.0)
    synthesis._record_call(user, 1000.0)
    assert synthesis._is_throttled(user, 1010.0)
    assert not synthesis._is_throttled(user, 1031.0)


def test_ai_throttle_memory_is_bounded(monkeypatch):
    monkeypatch.setattr(synthesis, "_last_generated", {})
    monkeypatch.setattr(synthesis.settings, "SYNTHESIS_RATE_LIMIT_SECONDS", 30)
    monkeypatch.setattr(synthesis, "MAX_THROTTLE_ENTRIES", 100)

    # Stale entries are dropped as soon as anyone makes a new call.
    for i in range(50):
        synthesis._record_call(uuid.uuid4(), float(i))
    synthesis._record_call(uuid.uuid4(), 10_000.0)
    assert len(synthesis._last_generated) == 1

    # A burst of distinct users inside the window never exceeds the cap.
    for i in range(500):
        synthesis._record_call(uuid.uuid4(), 20_000.0 + i * 0.001)
    assert len(synthesis._last_generated) <= 100
