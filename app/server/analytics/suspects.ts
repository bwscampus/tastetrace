import { Correlation, Meal, Symptom } from "@shared/schema";
import { localDate } from "./time";
import { clusterFlares, Flare, hoursBetween, mealsBefore } from "./flares";
import { mealItems, normalizeItem } from "./foods";
import { weekDates } from "./digest";

export type SuspectPair = {
  mealId: number;
  mealName: string;
  mealAt: Date;
  flareAt: Date;
  symptoms: string[];
  onsetHours: number;
};

export type Suspect = {
  name: string;
  flaresWithIngredient: number;
  flaresTotal: number;
  share: number;
  avgOnsetHours: number | null;
  timesLoggedThisWeek: number;
  exposuresAllTime: number;
  confidence: number;
  onWatchlist: boolean;
  recentPairs: SuspectPair[];
};

export type TimingWindow = { flares: number; topIngredients: string[] };

export type SuspectsDigest = {
  weekStart: string;
  weekEnd: string;
  windowHours: number;
  flares: number;
  mealsEvaluated: number;
  leadSuspect: string | null;
  symptomFilters: { name: string; count: number }[];
  ingredients: Suspect[];
  timingWindows: { "0to4h": TimingWindow; "4to12h": TimingWindow; "12to24h": TimingWindow };
};

function round1(n: number): number {
  return Math.round(n * 10) / 10;
}

/**
 * Which ingredients showed up in the window before this week's flares.
 * `meals`/`symptoms` are full history; `symptomFilter` narrows the flares.
 */
export function computeSuspects(
  meals: Meal[],
  symptoms: Symptom[],
  correlations: Correlation[],
  watchlist: string[],
  weekStart: string,
  tz: string,
  windowHours: number,
  symptomFilter?: string | null,
): SuspectsDigest {
  const dates = weekDates(weekStart);
  const inWeek = new Set(dates);
  const weekSymptoms = symptoms.filter((s) => inWeek.has(localDate(s.timestamp, tz)));
  const allFlares = clusterFlares(weekSymptoms);

  const symptomFilters = [{ name: "All Symptoms", count: allFlares.length }];
  for (const name of [...new Set(weekSymptoms.map((s) => s.name))].sort()) {
    symptomFilters.push({ name, count: allFlares.filter((f) => f.names.includes(name)).length });
  }

  const flares = symptomFilter ? allFlares.filter((f) => f.names.includes(symptomFilter)) : allFlares;
  const watch = new Set(watchlist.map(normalizeItem));

  // Ingredient exposures before each flare
  type Hit = { flare: Flare; meal: Meal; onset: number };
  const hitsByItem = new Map<string, { display: string; hits: Hit[]; flares: Set<Flare> }>();
  const evaluated = new Set<number>();
  for (const flare of flares) {
    for (const meal of mealsBefore(meals, flare.start, windowHours)) {
      evaluated.add(meal.id);
      const onset = hoursBetween(meal.timestamp, flare.start);
      for (const item of mealItems(meal).filter((i) => i.dimension === "ingredient")) {
        const entry = hitsByItem.get(item.key) ?? { display: item.display, hits: [], flares: new Set() };
        // Only the most recent exposure per flare counts for onset
        if (!entry.flares.has(flare)) entry.hits.push({ flare, meal, onset });
        entry.flares.add(flare);
        hitsByItem.set(item.key, entry);
      }
    }
  }

  const weekMeals = meals.filter((m) => inWeek.has(localDate(m.timestamp, tz)));
  const countItem = (list: Meal[], key: string) => list.filter((m) => mealItems(m).some((i) => i.dimension === "ingredient" && i.key === key)).length;
  const confidenceFor = (key: string) => Math.max(0, ...correlations
    .filter((c) => c.dimension === "ingredient" && normalizeItem(c.foodName) === key && (!symptomFilter || c.symptomName === symptomFilter))
    .map((c) => c.confidence));

  const ingredients: Suspect[] = [...hitsByItem.entries()]
    .map(([key, entry]) => ({
      name: entry.display,
      flaresWithIngredient: entry.flares.size,
      flaresTotal: flares.length,
      share: flares.length ? Math.round(entry.flares.size / flares.length * 100) / 100 : 0,
      avgOnsetHours: entry.hits.length ? round1(entry.hits.reduce((s, h) => s + h.onset, 0) / entry.hits.length) : null,
      timesLoggedThisWeek: countItem(weekMeals, key),
      exposuresAllTime: countItem(meals, key),
      confidence: confidenceFor(key),
      onWatchlist: watch.has(key),
      recentPairs: entry.hits
        .sort((a, b) => b.flare.start.getTime() - a.flare.start.getTime())
        .slice(0, 3)
        .map((h) => ({ mealId: h.meal.id, mealName: h.meal.name, mealAt: h.meal.timestamp, flareAt: h.flare.start, symptoms: h.flare.names, onsetHours: round1(h.onset) })),
    }))
    .sort((a, b) => b.share - a.share || b.confidence - a.confidence || a.name.localeCompare(b.name))
    .slice(0, 5);

  // Timing windows by the most recent meal before each flare
  const windows = { "0to4h": { flares: 0, items: new Map<string, number>() }, "4to12h": { flares: 0, items: new Map<string, number>() }, "12to24h": { flares: 0, items: new Map<string, number>() } };
  for (const flare of flares) {
    const [latest] = mealsBefore(meals, flare.start, windowHours);
    if (!latest) continue;
    const onset = hoursBetween(latest.timestamp, flare.start);
    const bucket = onset <= 4 ? windows["0to4h"] : onset <= 12 ? windows["4to12h"] : windows["12to24h"];
    bucket.flares++;
    for (const item of mealItems(latest).filter((i) => i.dimension === "ingredient")) {
      bucket.items.set(item.display, (bucket.items.get(item.display) ?? 0) + 1);
    }
  }
  const finish = (w: { flares: number; items: Map<string, number> }): TimingWindow => ({
    flares: w.flares,
    topIngredients: [...w.items.entries()].sort((a, b) => b[1] - a[1]).slice(0, 3).map(([name]) => name),
  });

  return {
    weekStart,
    weekEnd: dates[6],
    windowHours,
    flares: flares.length,
    mealsEvaluated: evaluated.size,
    leadSuspect: ingredients[0]?.name ?? null,
    symptomFilters,
    ingredients,
    timingWindows: { "0to4h": finish(windows["0to4h"]), "4to12h": finish(windows["4to12h"]), "12to24h": finish(windows["12to24h"]) },
  };
}
