"""Security hardening round 1: CSV formula injection and the AI throttle's memory."""

import uuid

from app.ai import synthesis
from app.ai.throttle import Throttle
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


def test_ai_throttle_blocks_a_second_call_within_the_window():
    throttle = Throttle(lambda: 30)
    user = uuid.uuid4()
    assert not throttle.is_throttled(user, 1000.0)
    throttle.record(user, 1000.0)
    assert throttle.is_throttled(user, 1010.0)
    assert not throttle.is_throttled(user, 1031.0)


def test_ai_throttle_reports_when_the_caller_may_retry():
    throttle = Throttle(lambda: 30)
    user = uuid.uuid4()
    assert throttle.retry_after(user, 1000.0) == 0  # never called
    throttle.record(user, 1000.0)
    assert throttle.retry_after(user, 1010.0) == 21  # rounded up, so never 0 too early
    assert throttle.retry_after(user, 1031.0) == 0


def test_ai_throttle_memory_is_bounded():
    throttle = Throttle(lambda: 30, max_entries=100)

    # Stale entries are dropped as soon as anyone makes a new call.
    for i in range(50):
        throttle.record(uuid.uuid4(), float(i))
    throttle.record(uuid.uuid4(), 10_000.0)
    assert len(throttle) == 1

    # A burst of distinct users inside the window never exceeds the cap.
    for i in range(500):
        throttle.record(uuid.uuid4(), 20_000.0 + i * 0.001)
    assert len(throttle) <= 100


def test_each_caller_gets_an_independent_throttle():
    """The photo path must not be blocked by a digest summary, or vice versa."""
    user = uuid.uuid4()
    synthesis.throttle.clear()
    other = Throttle(lambda: 30)
    synthesis.throttle.record(user, 1000.0)
    assert synthesis.throttle.is_throttled(user, 1001.0)
    assert not other.is_throttled(user, 1001.0)
    synthesis.throttle.clear()
