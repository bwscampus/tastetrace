import { Meal, UserSettings } from "@shared/schema";
import { addDays, localDate, localTime } from "./time";

export const COVERAGE_SLOTS = ["Breakfast", "Lunch", "Dinner"] as const;
export type CoverageSlot = (typeof COVERAGE_SLOTS)[number];

export type SlotStatus = { logged: boolean; mealId?: number; time?: string };

export type DayCoverage = {
  date: string;
  weekday: string;
  meals: number;
  slotsLogged: number;
  metThreshold: boolean;
};

export type Coverage = {
  date: string;
  slots: Record<CoverageSlot, SlotStatus>;
  loggedCount: number;
  slotTotal: number;
  percent: number;
  streak: { days: number; threshold: number; rule: string; todayCounts: boolean };
  week: DayCoverage[];
  weekSlots: {
    logged: number;
    total: number;
    bySlot: Record<CoverageSlot, { logged: number; total: number }>;
  };
  nudge: { time: string; enabled: boolean };
};

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function weekdayOf(date: string): string {
  const [y, m, d] = date.split("-").map(Number);
  return WEEKDAYS[new Date(Date.UTC(y, m - 1, d)).getUTCDay()];
}

/** Meals grouped by local date, with the earliest meal per slot. */
function groupByDay(meals: Meal[], tz: string) {
  const days = new Map<string, { meals: Meal[]; slots: Partial<Record<CoverageSlot, Meal>> }>();
  for (const meal of meals) {
    const date = localDate(meal.timestamp, tz);
    const day = days.get(date) ?? { meals: [], slots: {} };
    day.meals.push(meal);
    const slot = meal.mealType as CoverageSlot;
    if ((COVERAGE_SLOTS as readonly string[]).includes(slot)) {
      const current = day.slots[slot];
      if (!current || meal.timestamp < current.timestamp) day.slots[slot] = meal;
    }
    days.set(date, day);
  }
  return days;
}

/**
 * Daily coverage for `date` plus the trailing week and the current streak.
 * `meals` must include everything from the start of the streak lookback.
 */
export function computeCoverage(meals: Meal[], date: string, tz: string, settings: UserSettings): Coverage {
  const days = groupByDay(meals, tz);
  const threshold = settings.streakMealsPerDay;
  const today = days.get(date);

  const slots = Object.fromEntries(
    COVERAGE_SLOTS.map((slot) => {
      const meal = today?.slots[slot];
      return [slot, meal ? { logged: true, mealId: meal.id, time: localTime(meal.timestamp, tz) } : { logged: false }];
    }),
  ) as Record<CoverageSlot, SlotStatus>;
  const loggedCount = COVERAGE_SLOTS.filter((slot) => slots[slot].logged).length;

  // Trailing 7 days ending on `date`
  const week: DayCoverage[] = [];
  for (let i = 6; i >= 0; i--) {
    const d = addDays(date, -i);
    const day = days.get(d);
    const mealsCount = day?.meals.length ?? 0;
    week.push({
      date: d,
      weekday: weekdayOf(d),
      meals: mealsCount,
      slotsLogged: day ? COVERAGE_SLOTS.filter((slot) => day.slots[slot]).length : 0,
      metThreshold: mealsCount >= threshold,
    });
  }

  // Streak: consecutive days meeting the threshold ending on `date`, or on
  // the day before when `date` hasn't met it yet (the day is still open).
  const todayCounts = (today?.meals.length ?? 0) >= threshold;
  let cursor = todayCounts ? date : addDays(date, -1);
  let streakDays = 0;
  while ((days.get(cursor)?.meals.length ?? 0) >= threshold) {
    streakDays++;
    cursor = addDays(cursor, -1);
  }

  const bySlot = Object.fromEntries(
    COVERAGE_SLOTS.map((slot) => [slot, { logged: week.filter((d) => days.get(d.date)?.slots[slot]).length, total: 7 }]),
  ) as Record<CoverageSlot, { logged: number; total: number }>;

  return {
    date,
    slots,
    loggedCount,
    slotTotal: COVERAGE_SLOTS.length,
    percent: Math.round((loggedCount / COVERAGE_SLOTS.length) * 100),
    streak: { days: streakDays, threshold, rule: `${threshold}+ Meals/Day`, todayCounts },
    week,
    weekSlots: {
      logged: Object.values(bySlot).reduce((sum, s) => sum + s.logged, 0),
      total: COVERAGE_SLOTS.length * 7,
      bySlot,
    },
    nudge: { time: settings.nudgeTime, enabled: settings.nudgesEnabled },
  };
}
