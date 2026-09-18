import { describe, it, expect } from "vitest";
import { rulesSynthesis } from "../server/ai/rules";
import type { SuspectsDigest } from "../server/analytics/suspects";

const base: SuspectsDigest = {
  weekStart: "2026-09-11", weekEnd: "2026-09-17", windowHours: 24, flares: 2, mealsEvaluated: 2, leadSuspect: "sourdough bread",
  symptomFilters: [], ingredients: [], timingWindows: { "0to4h": { flares: 2, topIngredients: [] }, "4to12h": { flares: 0, topIngredients: [] }, "12to24h": { flares: 0, topIngredients: [] } },
};

describe("rulesSynthesis", () => {
  it("describes the lead suspect with its numbers and a caveat", () => {
    const { text, suggestedWatchlist } = rulesSynthesis({
      ...base,
      ingredients: [{ name: "sourdough bread", flaresWithIngredient: 1, flaresTotal: 2, share: 0.5, avgOnsetHours: 1.7, timesLoggedThisWeek: 1, exposuresAllTime: 6, confidence: 38, onWatchlist: false, recentPairs: [] }],
    });
    expect(text).toContain("sourdough bread appeared in 1 of 2 flare windows (50%)");
    expect(text).toContain("1.7 hours");
    expect(text).toContain("observed associations");
    expect(suggestedWatchlist).toEqual(["sourdough bread"]);
  });

  it("handles weeks without flares or without meals", () => {
    expect(rulesSynthesis({ ...base, flares: 0 }).text).toContain("No flare-ups");
    expect(rulesSynthesis(base).text).toContain("no meals were recorded");
  });
});
