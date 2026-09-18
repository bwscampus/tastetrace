import { Meal, Symptom } from "@shared/schema";
import { mealItems, Dimension } from "./foods";
import { hoursBetween } from "./flares";

export type EngineSettings = { correlationWindowHours: number; minTriggerCount: number };

export type CorrelationRow = {
  foodName: string;
  symptomName: string;
  dimension: Dimension;
  exposures: number;
  flareExposures: number;
  hitRate: number;
  baselineRate: number;
  lift: number;
  avgOnsetHours: number | null;
  lastFlareAt: Date | null;
  confidence: number;
  windowHours: number;
  // Legacy columns the web app reads
  occurrences: number;
  isIngredient: boolean;
};

export type Tier = "strong" | "likely" | "watch";

export function tierFor(confidence: number): Tier {
  if (confidence >= 75) return "strong";
  if (confidence >= 50) return "likely";
  return "watch";
}

/**
 * Confidence 0-100 from how often an item was followed by the symptom,
 * how much evidence there is, and how that compares with the symptom's
 * base rate after any meal.
 */
export function confidenceScore(hitRate: number, flareExposures: number, lift: number, dimension: Dimension): number {
  const support = 1 - Math.exp(-flareExposures / 2);
  const liftFactor = Math.min(Math.max(lift / 2, 0), 1);
  let confidence = Math.round(100 * hitRate * support * (0.5 + 0.5 * liftFactor));
  if (dimension === "cook_method") confidence -= 10;
  return Math.min(Math.max(confidence, 0), 100);
}

/**
 * Computes every (item, symptom) association for a user. Pure: takes all
 * meals and symptoms, returns the rows to store.
 */
export function computeCorrelations(meals: Meal[], symptoms: Symptom[], settings: EngineSettings): CorrelationRow[] {
  const W = settings.correlationWindowHours;
  if (meals.length === 0 || symptoms.length === 0) return [];

  const symptomNames = [...new Set(symptoms.map((s) => s.name))];
  const bySymptom = new Map<string, Symptom[]>();
  for (const s of symptoms) {
    const list = bySymptom.get(s.name) ?? [];
    list.push(s);
    bySymptom.set(s.name, list);
  }

  // followed[mealIndex][symptomName] = { onsetHours, at } for the first
  // occurrence of that symptom within the window after the meal
  type Follow = { onsetHours: number; at: Date };
  const followed: Map<string, Follow>[] = meals.map((meal) => {
    const map = new Map<string, Follow>();
    for (const name of symptomNames) {
      let best: Follow | undefined;
      for (const s of bySymptom.get(name)!) {
        const h = hoursBetween(meal.timestamp, s.timestamp);
        if (h > 0 && h <= W && (!best || h < best.onsetHours)) best = { onsetHours: h, at: s.timestamp };
      }
      if (best) map.set(name, best);
    }
    return map;
  });

  const baseline = new Map<string, number>();
  for (const name of symptomNames) {
    const count = followed.filter((f) => f.has(name)).length;
    baseline.set(name, count / meals.length);
  }

  // Group meal indexes by item
  const byItem = new Map<string, { display: string; dimension: Dimension; key: string; mealIndexes: number[] }>();
  meals.forEach((meal, index) => {
    for (const item of mealItems(meal)) {
      const id = `${item.dimension}:${item.key}`;
      const entry = byItem.get(id) ?? { display: item.display, dimension: item.dimension, key: item.key, mealIndexes: [] };
      entry.mealIndexes.push(index);
      byItem.set(id, entry);
    }
  });

  const rows: CorrelationRow[] = [];
  for (const item of byItem.values()) {
    for (const name of symptomNames) {
      const exposures = item.mealIndexes.length;
      const hits = item.mealIndexes.map((i) => followed[i].get(name)).filter((f): f is Follow => !!f);
      const flareExposures = hits.length;
      if (flareExposures === 0) continue;

      const hitRate = flareExposures / exposures;
      const base = baseline.get(name) ?? 0;
      const lift = base > 0 ? Math.min(hitRate / base, 5) : 5;
      let confidence = confidenceScore(hitRate, flareExposures, lift, item.dimension);
      if (exposures < 2 || flareExposures < settings.minTriggerCount) confidence = Math.min(confidence, 49);

      rows.push({
        foodName: item.display,
        symptomName: name,
        dimension: item.dimension,
        exposures,
        flareExposures,
        hitRate,
        baselineRate: base,
        lift,
        avgOnsetHours: hits.reduce((sum, h) => sum + h.onsetHours, 0) / flareExposures,
        lastFlareAt: new Date(Math.max(...hits.map((h) => h.at.getTime()))),
        confidence,
        windowHours: W,
        occurrences: flareExposures,
        isIngredient: item.dimension !== "food",
      });
    }
  }

  return rows.sort((a, b) => b.confidence - a.confidence || b.flareExposures - a.flareExposures || a.foodName.localeCompare(b.foodName));
}

/**
 * Symptom names that followed a meal within the window, and whether any of
 * the meal's items is a confident trigger for one of them.
 */
export type SuspicionRow = { foodName: string; symptomName: string; dimension: string; confidence: number };

export function suspicionFor(meal: Meal, symptoms: Symptom[], rows: SuspicionRow[], settings: { correlationWindowHours: number; minConfidence: number }) {
  const names = new Set<string>();
  for (const s of symptoms) {
    const h = hoursBetween(meal.timestamp, s.timestamp);
    if (h > 0 && h <= settings.correlationWindowHours) names.add(s.name);
  }
  if (names.size === 0) return { suspiciousFor: [] as string[], suspicion: null as "window" | "correlated" | null };

  const itemKeys = new Set(mealItems(meal).map((i) => `${i.dimension}:${i.key}`));
  const correlated = rows.some((r) =>
    names.has(r.symptomName) && r.confidence >= settings.minConfidence && itemKeys.has(`${r.dimension}:${r.foodName.trim().toLowerCase().replace(/\s+/g, " ")}`));
  return { suspiciousFor: [...names], suspicion: correlated ? "correlated" as const : "window" as const };
}
