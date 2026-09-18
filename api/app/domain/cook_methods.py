"""Preparation styles offered by the app; also a trigger dimension."""

COOK_METHODS: tuple[str, ...] = (
    "raw",
    "grilled",
    "fried",
    "deep_fried",
    "baked",
    "roasted",
    "boiled",
    "steamed",
    "sauteed",
    "smoked",
    "fermented",
    "processed",
    "toasted",
)


def is_cook_method(value: str) -> bool:
    return value in COOK_METHODS
