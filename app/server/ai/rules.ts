import type { SuspectsDigest } from "../analytics/suspects";

/**
 * Template summary used when no API key is configured or the model call
 * fails. Mirrors the tone of the AI synthesis: observational, hedged.
 */
export function rulesSynthesis(suspects: SuspectsDigest): { text: string; suggestedWatchlist: string[] } {
  if (suspects.flares === 0) {
    return {
      text: "No flare-ups were logged in this window, so there is nothing to correlate yet. Keep logging meals and symptoms and this summary will describe what tends to come before your flares.",
      suggestedWatchlist: [],
    };
  }
  const lead = suspects.ingredients[0];
  if (!lead) {
    return {
      text: `${suspects.flares} flare${suspects.flares === 1 ? "" : "s"} were logged, but no meals were recorded in the ${suspects.windowHours} hours before them, so no ingredient can be linked yet. Logging meals around flare times will make the next summary more useful.`,
      suggestedWatchlist: [],
    };
  }
  const share = Math.round(lead.share * 100);
  const onset = lead.avgOnsetHours != null ? `an average meal-to-flare delay of ${lead.avgOnsetHours} hours` : "no clear onset timing";
  const others = suspects.ingredients.slice(1, 3).map((i) => i.name);
  const othersText = others.length ? ` ${others.join(" and ")} also appeared before flares.` : "";
  const caveat = suspects.flares < 4
    ? " These are only observed associations rather than proof of a trigger, and the small number of windows means there is still considerable uncertainty."
    : " These are observed associations, not proof of a trigger; a consistent pattern across more weeks would make the link stronger.";
  return {
    text: `In the ${suspects.windowHours}-hour lookback before flares, ${lead.name} appeared in ${lead.flaresWithIngredient} of ${lead.flaresTotal} flare windows (${share}%), with ${onset}.${othersText}${caveat}`,
    suggestedWatchlist: lead.share >= 0.5 && !lead.onWatchlist ? [lead.name] : [],
  };
}
