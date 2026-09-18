import { Meal } from "@shared/schema";

// Meal-name fragments that describe a restriction rather than a food
export const DIETARY_TAGS = [
  "gluten-free", "dairy-free", "grain-free", "sugar-free",
  "glutenfree", "dairyfree", "grainfree", "sugarfree",
];

export function isDietaryTag(text: string): boolean {
  const lower = text.toLowerCase();
  return DIETARY_TAGS.some((tag) => lower.includes(tag));
}

// Splits a meal name like "Chicken & rice with broccoli" into foods, keeping
// common compound names ("avocado toast") whole.
export function parseMealIntoFoods(mealName: string): string[] {
  const separators = [',', '&', ' and ', ' with ', '+', '/'];
  const compoundFoods = [
    'avocado toast', 'peanut butter', 'ice cream', 'fried rice', 'chicken sandwich',
    'tuna salad', 'caesar salad', 'grilled cheese', 'mac and cheese', 'fish and chips',
    'bread and butter', 'cookies and cream', 'salt and pepper', 'ham and cheese',
    'tomato soup', 'chicken soup', 'vegetable soup', 'apple pie', 'chocolate cake'
  ];

  const lowerMealName = mealName.toLowerCase().trim();
  if (compoundFoods.some(compound => lowerMealName === compound)) {
    return [mealName.trim()];
  }

  const containsMultipleFoods = separators.some(sep => {
    const index = mealName.toLowerCase().indexOf(sep.toLowerCase());
    if (index === -1) return false;
    const beforeSep = mealName.substring(0, index + sep.length).toLowerCase();
    const afterSep = mealName.substring(index).toLowerCase();
    return !compoundFoods.some(compound => beforeSep.includes(compound) || afterSep.includes(compound));
  });

  if (!containsMultipleFoods) {
    return [mealName.trim()];
  }

  let foods: string[] = [mealName];
  for (const separator of separators) {
    const temp: string[] = [];
    for (const food of foods) {
      const lowerFood = food.toLowerCase();
      if (!compoundFoods.some(compound => lowerFood.includes(compound))) {
        const escapedSeparator = separator.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        temp.push(...food.split(new RegExp(escapedSeparator, 'gi')));
      } else {
        temp.push(food);
      }
    }
    foods = temp;
  }

  return foods
    .map(food => food.trim())
    .filter(food => food.length > 0)
    .map(food => {
      food = food.replace(/^(a |an |some |the )/i, '');
      food = food.replace(/\s*\(.*?\)\s*/g, '');
      return food.trim();
    })
    .filter(food => food.length > 2);
}

export type Dimension = "food" | "ingredient" | "cook_method";

export type MealItem = { key: string; display: string; dimension: Dimension };

export function normalizeItem(text: string): string {
  return text.trim().toLowerCase().replace(/\s+/g, " ");
}

/**
 * The analysable items of a meal:
 * - food: whole foods parsed from the name (what the web app shows)
 * - ingredient: the explicit ingredient list, falling back to the parsed foods
 * - cook_method: distinct preparation styles from ingredientDetails
 */
export function mealItems(meal: Meal): MealItem[] {
  const items = new Map<string, MealItem>();
  const add = (text: string, dimension: Dimension) => {
    const key = normalizeItem(text);
    if (!key || isDietaryTag(key)) return;
    const id = `${dimension}:${key}`;
    if (!items.has(id)) items.set(id, { key, display: text.trim(), dimension });
  };

  if (!isDietaryTag(meal.name)) {
    for (const food of parseMealIntoFoods(meal.name)) add(food, "food");
  }

  const ingredientNames = meal.ingredientDetails?.length
    ? meal.ingredientDetails.map((i) => i.name)
    : meal.ingredients?.length
      ? meal.ingredients
      : parseMealIntoFoods(meal.name);
  for (const name of ingredientNames) add(name, "ingredient");

  for (const detail of meal.ingredientDetails ?? []) {
    if (detail.cookMethod) add(detail.cookMethod, "cook_method");
  }

  return [...items.values()];
}
