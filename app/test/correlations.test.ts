import { describe, it, expect } from "vitest";
import { computeCorrelations, confidenceScore, suspicionFor, tierFor } from "../server/analytics/correlations";
import { clusterFlares, onsetHours } from "../server/analytics/flares";
import { mealItems, parseMealIntoFoods } from "../server/analytics/foods";
import type { Meal, Symptom } from "../shared/schema";

let id = 1;
const meal = (iso: string, name: string, ingredientDetails?: { name: string; cookMethod?: string }[]): Meal =>
  ({ id: id++, userId: "u", name, mealType: "Lunch", timestamp: new Date(iso), ingredients: ingredientDetails?.map((i) => i.name) ?? [], ingredientDetails: ingredientDetails ?? null, date: iso.slice(0, 10) } as Meal);
const symptom = (iso: string, name: string, intensity = 3): Symptom =>
  ({ id: id++, userId: "u", name, severity: "Moderate", intensity, timestamp: new Date(iso), date: iso.slice(0, 10) } as Symptom);

const settings = { correlationWindowHours: 24, minTriggerCount: 2 };

describe("mealItems", () => {
  it("derives food, ingredient and cook-method items", () => {
    const items = mealItems(meal("2026-09-11T19:45:00Z", "Avocado Sourdough Toast", [{ name: "Sourdough Bread", cookMethod: "toasted" }, { name: "avocado" }, { name: "salt" }]));
    expect(items.map((i) => `${i.dimension}:${i.key}`)).toEqual([
      "food:avocado sourdough toast", "ingredient:sourdough bread", "ingredient:avocado", "ingredient:salt", "cook_method:toasted",
    ]);
    expect(items[1].display).toBe("Sourdough Bread");
  });

  it("falls back to parsed foods when there is no ingredient list and skips dietary tags", () => {
    expect(mealItems(meal("2026-09-11T19:45:00Z", "Chicken & rice with broccoli")).map((i) => i.key)).toEqual([
      "food:chicken", "food:rice", "food:broccoli", "ingredient:chicken", "ingredient:rice", "ingredient:broccoli",
    ].map((k) => k.split(":")[1]));
    expect(mealItems(meal("2026-09-11T19:45:00Z", "Gluten-free pasta"))).toEqual([]);
    expect(parseMealIntoFoods("mac and cheese")).toEqual(["mac and cheese"]);
  });
});

describe("flares", () => {
  it("clusters symptoms within 30 minutes and finds the onset meal", () => {
    const flares = clusterFlares([
      symptom("2026-09-11T21:29:00Z", "Acid Reflux", 3), symptom("2026-09-11T21:40:00Z", "Bloating", 1),
      symptom("2026-09-12T10:00:00Z", "Headache", 4),
    ]);
    expect(flares).toHaveLength(2);
    expect(flares[0].names).toEqual(["Acid Reflux", "Bloating"]);
    expect(flares[0].maxIntensity).toBe(3);
    const meals = [meal("2026-09-11T19:45:00Z", "Toast"), meal("2026-09-10T19:45:00Z", "Old")];
    expect(onsetHours(meals, flares[0].start, 24)).toBeCloseTo(1.73, 1);
    expect(onsetHours(meals, flares[1].start, 4)).toBeNull();
  });
});

describe("computeCorrelations", () => {
  it("scores items by hit rate with a denominator and lift", () => {
    // sourdough eaten 4 times, followed by reflux 3 times; oats eaten 4 times, never followed
    const meals = [
      meal("2026-09-01T12:00:00Z", "Toast", [{ name: "sourdough bread", cookMethod: "toasted" }]),
      meal("2026-09-02T12:00:00Z", "Toast", [{ name: "sourdough bread", cookMethod: "toasted" }]),
      meal("2026-09-03T12:00:00Z", "Toast", [{ name: "sourdough bread", cookMethod: "toasted" }]),
      meal("2026-09-04T12:00:00Z", "Toast", [{ name: "sourdough bread", cookMethod: "toasted" }]),
      meal("2026-09-05T12:00:00Z", "Oats", [{ name: "oats" }]),
      meal("2026-09-06T12:00:00Z", "Oats", [{ name: "oats" }]),
      meal("2026-09-07T12:00:00Z", "Oats", [{ name: "oats" }]),
      meal("2026-09-08T12:00:00Z", "Oats", [{ name: "oats" }]),
    ];
    const symptoms = [
      symptom("2026-09-01T14:00:00Z", "Acid Reflux"), symptom("2026-09-02T14:00:00Z", "Acid Reflux"), symptom("2026-09-03T14:00:00Z", "Acid Reflux"),
    ];
    const rows = computeCorrelations(meals, symptoms, settings);
    const sourdough = rows.find((r) => r.dimension === "ingredient" && r.foodName === "sourdough bread")!;
    expect(sourdough).toMatchObject({ exposures: 4, flareExposures: 3, hitRate: 0.75, baselineRate: 3 / 8, lift: 2, occurrences: 3, isIngredient: true, windowHours: 24 });
    expect(sourdough.avgOnsetHours).toBe(2);
    expect(sourdough.confidence).toBe(confidenceScore(0.75, 3, 2, "ingredient"));
    expect(sourdough.confidence).toBeGreaterThanOrEqual(50);
    expect(tierFor(sourdough.confidence)).toBe("likely");

    // Cook method rows are penalised; oats never precede a flare so they are absent
    const toasted = rows.find((r) => r.dimension === "cook_method")!;
    expect(toasted.confidence).toBe(sourdough.confidence - 10);
    expect(rows.some((r) => r.foodName === "oats")).toBe(false);
    // A whole-food row exists for the web app
    expect(rows.some((r) => r.dimension === "food" && r.foodName === "Toast" && !r.isIngredient)).toBe(true);
  });

  it("caps confidence below 50 when evidence is thin", () => {
    const rows = computeCorrelations(
      [meal("2026-09-01T12:00:00Z", "Toast", [{ name: "sourdough bread" }])],
      [symptom("2026-09-01T14:00:00Z", "Acid Reflux")],
      settings,
    );
    expect(rows[0].confidence).toBeLessThanOrEqual(49);
    expect(computeCorrelations([], [], settings)).toEqual([]);
  });

  it("marks meals followed by a symptom as suspicious, upgraded when an item is a known trigger", () => {
    const m = meal("2026-09-11T19:45:00Z", "Avocado Sourdough Toast", [{ name: "sourdough bread" }]);
    const s = [symptom("2026-09-11T21:29:00Z", "Acid Reflux")];
    expect(suspicionFor(m, s, [], { correlationWindowHours: 24, minConfidence: 50 })).toEqual({ suspiciousFor: ["Acid Reflux"], suspicion: "window" });
    const rows = [{ foodName: "Sourdough Bread", symptomName: "Acid Reflux", dimension: "ingredient" as const, confidence: 72 }];
    expect(suspicionFor(m, s, rows, { correlationWindowHours: 24, minConfidence: 50 }).suspicion).toBe("correlated");
    expect(suspicionFor(m, s, rows, { correlationWindowHours: 1, minConfidence: 50 }).suspicion).toBeNull();
  });
});
