// Preparation styles that can be attached to an ingredient. Mirrored in the iOS app.
export const COOK_METHODS = [
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
] as const;

export type CookMethod = (typeof COOK_METHODS)[number];

export function isCookMethod(value: string): value is CookMethod {
  return (COOK_METHODS as readonly string[]).includes(value);
}
