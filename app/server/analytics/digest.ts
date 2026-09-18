import { Correlation, Meal, Symptom, UserSettings } from "@shared/schema";
import { addDays, localDate } from "./time";
import { clusterFlares, intensityOf, onsetHours } from "./flares";
import { COVERAGE_SLOTS } from "./coverage";
import { catalogItemByKey, catalogItemByName } from "@shared/symptomCatalog";

export type DayTrend = {
  date: string;
  weekday: string;
  index: number;
  occurrences: number;
  maxIntensity: number;
  level: "zero" | "moderate" | "high";
};

export type SymptomCard = {
  name: string;
  catalogKey: string | null;
  emoji: string | null;
  occurrences: number;
  shareOfWeek: number;
  avgSeverity10: number;
  avgDurationMinutes: number | null;
  peakDay: string | null;
  vsBaseline: "up" | "same" | "down";
  topTriggers: string[];
};

export type WeeklyDigest = {
  weekStart: string;
  weekEnd: string;
  previousWeekStart: string;
  hasNextWeek: boolean;
  trends: {
    index: number;
    baselineIndex: number;
    deltaVsBaselinePercent: number;
    previousWeekIndex: number;
    changeVsPreviousPercent: number;
    occurrences: number;
    flares: number;
    discomfortFreeDays: number;
    severeDays: number;
    severePeakDay: string | null;
    mealLogDepth: number;
    dataCompleteness: "complete" | "partial" | "empty";
    days: DayTrend[];
  };
  symptoms: {
    total: number;
    baselinePerWeek: number;
    vsBaseline: "up" | "same" | "down";
    distinct: number;
    distribution: { name: string; catalogKey: string | null; count: number; share: number }[];
    cards: SymptomCard[];
    onsetWindows: { under1h: number; from1to3h: number; over3h: number; unmatched: number };
  };
};

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
function weekdayOf(date: string): string {
  const [y, m, d] = date.split("-").map(Number);
  return WEEKDAYS[new Date(Date.UTC(y, m - 1, d))!.getUTCDay()];
}

export function weekDates(weekStart: string): string[] {
  return Array.from({ length: 7 }, (_, i) => addDays(weekStart, i));
}

/** Discomfort index for one day: max intensity × 2 (0 when nothing logged). */
function dayIndex(symptoms: Symptom[]): number {
  return symptoms.length === 0 ? 0 : Math.max(...symptoms.map(intensityOf)) * 2;
}

export function levelFor(index: number): DayTrend["level"] {
  if (index === 0) return "zero";
  return index >= 5 ? "high" : "moderate";
}

function round1(n: number): number {
  return Math.round(n * 10) / 10;
}

function compare(value: number, baseline: number): "up" | "same" | "down" {
  if (baseline === 0) return value === 0 ? "same" : "up";
  const ratio = value / baseline;
  if (ratio > 1.2) return "up";
  if (ratio < 0.8) return "down";
  return "same";
}

/**
 * Weekly digest for the 7 days starting at `weekStart`. `symptoms` and
 * `meals` are the user's full history so baselines can be computed.
 */
export function computeWeeklyDigest(
  meals: Meal[],
  symptoms: Symptom[],
  correlations: Correlation[],
  weekStart: string,
  tz: string,
  settings: UserSettings,
  today: string,
): WeeklyDigest {
  const dates = weekDates(weekStart);
  const weekEnd = dates[6];
  const inWeek = new Set(dates);

  const symptomsByDay = new Map<string, Symptom[]>();
  for (const s of symptoms) {
    const d = localDate(s.timestamp, tz);
    symptomsByDay.set(d, [...(symptomsByDay.get(d) ?? []), s]);
  }
  const mealsByDay = new Map<string, Meal[]>();
  for (const m of meals) {
    const d = localDate(m.timestamp, tz);
    mealsByDay.set(d, [...(mealsByDay.get(d) ?? []), m]);
  }

  // Trends
  const days: DayTrend[] = dates.map((date) => {
    const list = symptomsByDay.get(date) ?? [];
    const index = dayIndex(list);
    return { date, weekday: weekdayOf(date), index, occurrences: list.length, maxIntensity: list.length ? Math.max(...list.map(intensityOf)) : 0, level: levelFor(index) };
  });
  const weekIndex = days.reduce((sum, d) => sum + d.index, 0) / 7;

  // Baseline: mean daily index over every day since the first log
  const allDates = [...new Set([...symptomsByDay.keys(), ...mealsByDay.keys()])].sort();
  let baselineIndex = 0;
  if (allDates.length > 0) {
    const first = allDates[0];
    const last = today > weekEnd ? today : weekEnd;
    let cursor = first;
    let total = 0;
    let count = 0;
    while (cursor <= last && count < 3660) {
      total += dayIndex(symptomsByDay.get(cursor) ?? []);
      count++;
      cursor = addDays(cursor, 1);
    }
    baselineIndex = count ? total / count : 0;
  }

  const previousWeekStart = addDays(weekStart, -7);
  const previousIndex = weekDates(previousWeekStart).reduce((sum, d) => sum + dayIndex(symptomsByDay.get(d) ?? []), 0) / 7;

  const weekSymptoms = dates.flatMap((d) => symptomsByDay.get(d) ?? []);
  const weekMeals = dates.flatMap((d) => mealsByDay.get(d) ?? []);
  const flares = clusterFlares(weekSymptoms);
  const severe = days.filter((d) => d.level === "high");
  const peak = [...days].sort((a, b) => b.index - a.index)[0];

  const slotsLogged = dates.reduce((sum, d) => {
    const types = new Set((mealsByDay.get(d) ?? []).map((m) => m.mealType));
    return sum + COVERAGE_SLOTS.filter((slot) => types.has(slot)).length;
  }, 0);

  const loggedDays = dates.filter((d) => (mealsByDay.get(d)?.length ?? 0) > 0 || (symptomsByDay.get(d)?.length ?? 0) > 0).length;
  const elapsedDays = dates.filter((d) => d <= today).length;
  const dataCompleteness = loggedDays === 0 ? "empty" : loggedDays >= elapsedDays ? "complete" : "partial";

  // Symptoms section
  const byName = new Map<string, Symptom[]>();
  for (const s of weekSymptoms) byName.set(s.name, [...(byName.get(s.name) ?? []), s]);

  const historyWeeks = Math.max(1, allDates.length ? Math.ceil((daysBetween(allDates[0], today) + 1) / 7) : 1);
  const baselinePerWeek = symptoms.length / historyWeeks;
  const historyByName = new Map<string, number>();
  for (const s of symptoms) historyByName.set(s.name, (historyByName.get(s.name) ?? 0) + 1);

  const cards: SymptomCard[] = [...byName.entries()]
    .map(([name, list]) => {
      const catalog = catalogItemByKey(list[0].catalogKey) ?? catalogItemByName(name);
      const durations = list.map((s) => s.durationMinutes).filter((d): d is number => d != null);
      const perDay = new Map<string, number>();
      for (const s of list) {
        const d = localDate(s.timestamp, tz);
        perDay.set(d, (perDay.get(d) ?? 0) + 1);
      }
      const peakDay = [...perDay.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0]?.[0] ?? null;
      const triggers = correlations
        .filter((c) => c.symptomName === name && c.dimension === "ingredient")
        .sort((a, b) => b.confidence - a.confidence)
        .slice(0, 3)
        .map((c) => c.foodName);
      return {
        name,
        catalogKey: list[0].catalogKey ?? catalog?.key ?? null,
        emoji: catalog?.emoji ?? null,
        occurrences: list.length,
        shareOfWeek: round1(list.length / weekSymptoms.length * 100) / 100,
        avgSeverity10: round1(list.reduce((sum, s) => sum + intensityOf(s) * 2, 0) / list.length),
        avgDurationMinutes: durations.length ? Math.round(durations.reduce((a, b) => a + b, 0) / durations.length) : null,
        peakDay,
        vsBaseline: compare(list.length, (historyByName.get(name) ?? 0) / historyWeeks),
        topTriggers: triggers,
      };
    })
    .sort((a, b) => b.occurrences - a.occurrences || a.name.localeCompare(b.name));

  const onsetWindows = { under1h: 0, from1to3h: 0, over3h: 0, unmatched: 0 };
  for (const s of weekSymptoms) {
    const h = onsetHours(meals, s.timestamp, settings.correlationWindowHours);
    if (h == null) onsetWindows.unmatched++;
    else if (h < 1) onsetWindows.under1h++;
    else if (h <= 3) onsetWindows.from1to3h++;
    else onsetWindows.over3h++;
  }

  return {
    weekStart,
    weekEnd,
    previousWeekStart,
    hasNextWeek: addDays(weekStart, 7) <= today,
    trends: {
      index: round1(weekIndex),
      baselineIndex: round1(baselineIndex),
      deltaVsBaselinePercent: baselineIndex > 0 ? Math.round((weekIndex - baselineIndex) / baselineIndex * 100) : 0,
      previousWeekIndex: round1(previousIndex),
      changeVsPreviousPercent: previousIndex > 0 ? Math.round((weekIndex - previousIndex) / previousIndex * 100) : 0,
      occurrences: weekSymptoms.length,
      flares: flares.length,
      discomfortFreeDays: days.filter((d) => d.index === 0).length,
      severeDays: severe.length,
      severePeakDay: peak && peak.index > 0 ? peak.date : null,
      mealLogDepth: Math.round(slotsLogged / 21 * 100) / 100,
      dataCompleteness,
      days,
    },
    symptoms: {
      total: weekSymptoms.length,
      baselinePerWeek: round1(baselinePerWeek),
      vsBaseline: compare(weekSymptoms.length, baselinePerWeek),
      distinct: byName.size,
      distribution: cards.map((c) => ({ name: c.name, catalogKey: c.catalogKey, count: c.occurrences, share: c.shareOfWeek })),
      cards,
      onsetWindows,
    },
  };
}

function daysBetween(a: string, b: string): number {
  return Math.round((Date.parse(b) - Date.parse(a)) / 86_400_000);
}
