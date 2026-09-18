import { describe, it, expect } from "vitest";
import { computeWeeklyDigest } from "../server/analytics/digest";
import { computeSuspects } from "../server/analytics/suspects";
import type { Correlation, Meal, Symptom, UserSettings } from "../shared/schema";

let id = 1;
const meal = (iso: string, name: string, ingredients: string[], mealType = "Lunch"): Meal =>
  ({ id: id++, userId: "u", name, mealType, timestamp: new Date(iso), ingredients, ingredientDetails: ingredients.map((n) => ({ name: n })), date: iso.slice(0, 10) } as Meal);
const symptom = (iso: string, name: string, intensity: number, durationMinutes?: number): Symptom =>
  ({ id: id++, userId: "u", name, severity: "Moderate", intensity, durationMinutes: durationMinutes ?? null, catalogKey: name === "Acid Reflux" ? "acid_reflux" : "bloating", timestamp: new Date(iso), date: iso.slice(0, 10) } as Symptom);

const tz = "America/Los_Angeles";
const settings = { correlationWindowHours: 24, minTriggerCount: 2, minConfidence: 50 } as UserSettings;

// The mockup week: a flare on Friday Sep 11 (level 3 → index 6) and one on Thursday Sep 17
const meals = [
  meal("2026-09-11T19:45:00Z", "Avocado Sourdough Toast", ["sourdough bread", "avocado", "salt"]),
  meal("2026-09-17T19:45:00Z", "Avocado Sourdough Toast", ["sourdough bread", "avocado", "salt"]),
  meal("2026-09-14T15:00:00Z", "Oatmeal", ["oats"], "Breakfast"),
];
const symptoms = [
  symptom("2026-09-11T21:29:00Z", "Acid Reflux", 3, 60), symptom("2026-09-11T21:30:00Z", "Bloating", 1, 20),
  symptom("2026-09-17T21:29:00Z", "Acid Reflux", 3, 60), symptom("2026-09-17T21:30:00Z", "Bloating", 1, 20),
];
const correlations = [{ foodName: "sourdough bread", symptomName: "Acid Reflux", dimension: "ingredient", confidence: 62 }] as Correlation[];

describe("computeWeeklyDigest", () => {
  const digest = computeWeeklyDigest(meals, symptoms, correlations, "2026-09-11", tz, settings, "2026-09-17");

  it("computes the trends hero and per-day bars", () => {
    expect(digest.weekEnd).toBe("2026-09-17");
    expect(digest.trends.days.map((d) => d.index)).toEqual([6, 0, 0, 0, 0, 0, 6]);
    expect(digest.trends.days[0]).toMatchObject({ weekday: "Fri", level: "high", occurrences: 2, maxIntensity: 3 });
    expect(digest.trends.index).toBe(1.7);
    expect(digest.trends.baselineIndex).toBe(1.7); // all history is this week
    expect(digest.trends.deltaVsBaselinePercent).toBe(0);
    expect(digest.trends).toMatchObject({ occurrences: 4, flares: 2, discomfortFreeDays: 5, severeDays: 2, severePeakDay: "2026-09-11" });
    expect(digest.trends.mealLogDepth).toBe(0.14); // 2 lunches + 1 breakfast = 3 of 21 slots
    expect(digest.hasNextWeek).toBe(false);
  });

  it("builds symptom cards with severity, duration, peak day and triggers", () => {
    expect(digest.symptoms.total).toBe(4);
    expect(digest.symptoms.distinct).toBe(2);
    const reflux = digest.symptoms.cards.find((c) => c.name === "Acid Reflux")!;
    expect(reflux).toMatchObject({ emoji: "🔥", occurrences: 2, shareOfWeek: 0.5, avgSeverity10: 6, avgDurationMinutes: 60, peakDay: "2026-09-11", topTriggers: ["sourdough bread"] });
    expect(digest.symptoms.onsetWindows).toEqual({ under1h: 0, from1to3h: 4, over3h: 0, unmatched: 0 });
  });
});

describe("computeSuspects", () => {
  it("ranks ingredients by how many flares they preceded", () => {
    const suspects = computeSuspects(meals, symptoms, correlations, ["Sourdough Bread"], "2026-09-11", tz, 24, null);
    expect(suspects).toMatchObject({ flares: 2, mealsEvaluated: 2, leadSuspect: "sourdough bread", windowHours: 24 });
    expect(suspects.symptomFilters).toEqual([{ name: "All Symptoms", count: 2 }, { name: "Acid Reflux", count: 2 }, { name: "Bloating", count: 2 }]);
    const lead = suspects.ingredients[0];
    expect(lead).toMatchObject({ name: "sourdough bread", flaresWithIngredient: 2, flaresTotal: 2, share: 1, avgOnsetHours: 1.7, timesLoggedThisWeek: 2, exposuresAllTime: 2, confidence: 62, onWatchlist: true });
    expect(lead.recentPairs[0]).toMatchObject({ mealName: "Avocado Sourdough Toast", symptoms: ["Acid Reflux", "Bloating"], onsetHours: 1.7 });
    expect(suspects.timingWindows["0to4h"]).toMatchObject({ flares: 2, topIngredients: ["sourdough bread", "avocado", "salt"] });
    expect(suspects.timingWindows["12to24h"].flares).toBe(0);
    expect(suspects.ingredients.some((i) => i.name === "oats")).toBe(false);
  });

  it("filters by symptom", () => {
    const only = computeSuspects(meals, symptoms, correlations, [], "2026-09-11", tz, 24, "Bloating");
    expect(only.flares).toBe(2);
    expect(only.ingredients[0].confidence).toBe(0); // the stored correlation is for reflux
    expect(computeSuspects(meals, symptoms, correlations, [], "2026-09-18", tz, 24, null).flares).toBe(0);
  });
});
