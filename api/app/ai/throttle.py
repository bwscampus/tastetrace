"""A bounded per-user call throttle, for the model calls that cost money.

In-process, so it does not coordinate across replicas; the service runs a
single one today, and this weakens silently if that changes.

Memory is bounded two ways so a flood of fresh accounts cannot grow it without
limit: entries older than the window are dropped, because they can no longer
throttle anything, and past a hard cap the oldest go first. Insertion order is
call order, which is what makes "oldest first" a cheap scan from the front.

Each caller gets its own instance, so a photo call and a digest summary throttle
independently. The window is read through a callable rather than captured, so
settings stay live and a test can change them.
"""

from collections.abc import Callable
from uuid import UUID

DEFAULT_MAX_ENTRIES = 10_000


class Throttle:
    def __init__(
        self,
        window_seconds: Callable[[], float],
        max_entries: int = DEFAULT_MAX_ENTRIES,
    ) -> None:
        self._window = window_seconds
        self._max_entries = max_entries
        self._last_call: dict[UUID, float] = {}

    def is_throttled(self, user_id: UUID, now: float) -> bool:
        last = self._last_call.get(user_id)
        return last is not None and now - last < self._window()

    def record(self, user_id: UUID, now: float) -> None:
        self._last_call.pop(user_id, None)  # re-insert so order stays oldest-first
        self._last_call[user_id] = now
        window = self._window()
        for key in list(self._last_call):
            fresh = now - self._last_call[key] < window
            if fresh and len(self._last_call) <= self._max_entries:
                break
            del self._last_call[key]

    def retry_after(self, user_id: UUID, now: float) -> int:
        """Whole seconds until this user may call again; 0 when they may now."""
        last = self._last_call.get(user_id)
        if last is None:
            return 0
        remaining = self._window() - (now - last)
        return max(0, int(remaining) + 1) if remaining > 0 else 0

    # Testing helpers. Clearing is the only way to make a throttled user
    # callable again without waiting, which the retry tests need.
    def clear(self) -> None:
        self._last_call.clear()

    def __len__(self) -> int:
        return len(self._last_call)
