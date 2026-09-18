import { describe, it, expect } from "vitest";
import { computeCoverage } from "../server/analytics/coverage";
import type { Meal, UserSettings } from "../shared/schema";

const tz = "America/Los_Angeles";
const settings = { streakMealsPerDay: 2, nudgeTime: "20:30", nudgesEnabled: true } as UserSettings;

let nextId = 1;
function meal(iso: string, mealType: string): Meal {
  return { id: nextId++, mealType, timestamp: new Date(iso), name: "m", userId: "u", date: iso.slice(0, 10) } as Meal;
}

describe("computeCoverage", () => {
  it("fills slots from the earliest meal per slot and ignores snacks", () => {
    const meals = [
      meal("2026-09-17T15:15:00Z", "Breakfast"), // 08:15 local
      meal("2026-09-17T19:45:00Z", "Lunch"),
      meal("2026-09-17T18:00:00Z", "Lunch"),     // earlier lunch wins
      meal("2026-09-17T23:00:00Z", "Snack"),
    ];
    const c = computeCoverage(meals, "2026-09-17", tz, settings);
    expect(c.slots.Breakfast).toEqual({ logged: true, mealId: meals[0].id, time: "08:15" });
    expect(c.slots.Lunch.time).toBe("11:00");
    expect(c.slots.Dinner).toEqual({ logged: false });
    expect(c.loggedCount).toBe(2);
    expect(c.percent).toBe(67);
    expect(c.week).toHaveLength(7);
    expect(c.week[6]).toMatchObject({ date: "2026-09-17", weekday: "Thu", meals: 4, slotsLogged: 2, metThreshold: true });
    expect(c.weekSlots).toMatchObject({ logged: 2, total: 21 });
    expect(c.nudge).toEqual({ time: "20:30", enabled: true });
  });

  it("counts a streak of days meeting the threshold, allowing today to be open", () => {
    const meals = [
      meal("2026-09-15T15:00:00Z", "Breakfast"), meal("2026-09-15T20:00:00Z", "Lunch"),
      meal("2026-09-16T15:00:00Z", "Breakfast"), meal("2026-09-16T20:00:00Z", "Lunch"),
      meal("2026-09-17T15:00:00Z", "Breakfast"), // today: only one meal so far
    ];
    const open = computeCoverage(meals, "2026-09-17", tz, settings);
    expect(open.streak).toMatchObject({ days: 2, todayCounts: false, rule: "2+ Meals/Day" });

    const closed = computeCoverage([...meals, meal("2026-09-17T20:00:00Z", "Lunch")], "2026-09-17", tz, settings);
    expect(closed.streak).toMatchObject({ days: 3, todayCounts: true });

    const broken = computeCoverage(meals.filter((m) => !m.timestamp.toISOString().startsWith("2026-09-16")), "2026-09-17", tz, settings);
    expect(broken.streak.days).toBe(0);
  });

  it("buckets by the requested timezone", () => {
    const c = computeCoverage([meal("2026-09-18T02:00:00Z", "Dinner")], "2026-09-17", tz, settings); // 7pm Sep 17 in LA
    expect(c.slots.Dinner.logged).toBe(true);
    expect(computeCoverage([meal("2026-09-18T02:00:00Z", "Dinner")], "2026-09-17", "UTC", settings).slots.Dinner.logged).toBe(false);
  });
});
