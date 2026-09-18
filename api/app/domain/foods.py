"""Turning a meal into the items an association can be drawn against.

A meal contributes three kinds of item: the whole foods parsed out of its
name, the ingredients, and the cooking styles used on them.
"""

import re
from dataclasses import dataclass
from typing import Literal

from app.domain.rows import MealRow

Dimension = Literal["food", "ingredient", "cook_method"]

# Phrases that describe a restriction rather than a food
DIETARY_TAGS = (
    "gluten-free", "dairy-free", "grain-free", "sugar-free",
    "glutenfree", "dairyfree", "grainfree", "sugarfree",
)

_SEPARATORS = (",", "&", " and ", " with ", "+", "/")

# Names that contain a separator but mean one thing
_COMPOUND_FOODS = (
    "avocado toast", "peanut butter", "ice cream", "fried rice", "chicken sandwich",
    "tuna salad", "caesar salad", "grilled cheese", "mac and cheese", "fish and chips",
    "bread and butter", "cookies and cream", "salt and pepper", "ham and cheese",
    "tomato soup", "chicken soup", "vegetable soup", "apple pie", "chocolate cake",
)


def is_dietary_tag(text: str) -> bool:
    lowered = text.lower()
    return any(tag in lowered for tag in DIETARY_TAGS)


def normalize_item(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip().lower())


def parse_meal_into_foods(meal_name: str) -> list[str]:
    """Splits "Chicken & rice with broccoli" into its foods.

    Compound names ("mac and cheese") are left whole.
    """
    lowered = meal_name.strip().lower()
    if any(lowered == compound for compound in _COMPOUND_FOODS):
        return [meal_name.strip()]

    def separator_is_real(separator: str) -> bool:
        index = meal_name.lower().find(separator.lower())
        if index == -1:
            return False
        before = meal_name[: index + len(separator)].lower()
        after = meal_name[index:].lower()
        return not any(c in before or c in after for c in _COMPOUND_FOODS)

    if not any(separator_is_real(sep) for sep in _SEPARATORS):
        return [meal_name.strip()]

    foods = [meal_name]
    for separator in _SEPARATORS:
        split_out: list[str] = []
        for food in foods:
            if any(compound in food.lower() for compound in _COMPOUND_FOODS):
                split_out.append(food)
            else:
                split_out.extend(re.split(re.escape(separator), food, flags=re.IGNORECASE))
        foods = split_out

    cleaned: list[str] = []
    for food in foods:
        food = food.strip()
        if not food:
            continue
        food = re.sub(r"^(a |an |some |the )", "", food, count=1, flags=re.IGNORECASE)
        food = re.sub(r"\s*\(.*?\)\s*", "", food)
        food = food.strip()
        if len(food) > 2:
            cleaned.append(food)
    return cleaned


@dataclass(frozen=True)
class MealItem:
    key: str
    display: str
    dimension: Dimension

    @property
    def id(self) -> str:
        return f"{self.dimension}:{self.key}"


def meal_items(meal: MealRow) -> list[MealItem]:
    """Every analysable item of a meal, de-duplicated, in a stable order."""
    items: dict[str, MealItem] = {}

    def add(text: str, dimension: Dimension) -> None:
        key = normalize_item(text)
        if not key or is_dietary_tag(key):
            return
        item = MealItem(key=key, display=text.strip(), dimension=dimension)
        items.setdefault(item.id, item)

    if not is_dietary_tag(meal.name):
        for food in parse_meal_into_foods(meal.name):
            add(food, "food")

    if meal.ingredient_details:
        names = [detail.name for detail in meal.ingredient_details]
    elif meal.ingredients:
        names = list(meal.ingredients)
    else:
        names = parse_meal_into_foods(meal.name)
    for name in names:
        add(name, "ingredient")

    for detail in meal.ingredient_details or []:
        if detail.cook_method:
            add(detail.cook_method, "cook_method")

    return list(items.values())
