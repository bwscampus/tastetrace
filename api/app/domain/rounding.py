"""JavaScript-compatible rounding.

The TypeScript backend these numbers come from used Math.round, which rounds
half away from zero for positives; Python's round() is banker's rounding, so
round(0.5) is 0 and round(2.5) is 2. Every ported formula uses js_round.
"""

import math


def js_round(value: float) -> int:
    return math.floor(value + 0.5)


def round1(value: float) -> float:
    """One decimal place, half-up."""
    return js_round(value * 10) / 10


def round2(value: float) -> float:
    return js_round(value * 100) / 100
