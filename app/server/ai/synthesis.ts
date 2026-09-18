import { createHash } from "crypto";
import Anthropic from "@anthropic-ai/sdk";
import type { SuspectsDigest } from "../analytics/suspects";
import { rulesSynthesis } from "./rules";
import { storage } from "../storage";

export const SYNTHESIS_MODEL = "claude-opus-5";
const REQUEST_TIMEOUT_MS = 8000;
const RATE_LIMIT_MS = 30_000;

const SYSTEM_PROMPT = `You summarise a food-and-symptom journal for the person who wrote it.
You receive JSON describing which ingredients were eaten in the hours before their symptom flare-ups this week.
Write one short paragraph (at most 90 words) in plain prose, in the second person.
Only cite numbers that appear in the JSON. Say plainly that these are observed associations, not proof, and that few flare windows means uncertainty.
Do not diagnose, do not tell the person to eliminate foods, and do not give medical advice.`;

export type SynthesisResult = {
  text: string;
  source: "claude" | "rules";
  model: string | null;
  cached: boolean;
  generatedAt: Date;
  suggestedWatchlist: string[];
};

// Last generation per user, to keep a tapping user from burning calls
const lastGeneration = new Map<string, number>();

function hashInput(suspects: SuspectsDigest): string {
  const stable = {
    weekStart: suspects.weekStart,
    windowHours: suspects.windowHours,
    flares: suspects.flares,
    mealsEvaluated: suspects.mealsEvaluated,
    ingredients: suspects.ingredients.map((i) => [i.name, i.flaresWithIngredient, i.flaresTotal, i.avgOnsetHours, i.timesLoggedThisWeek]),
    timingWindows: suspects.timingWindows,
  };
  return createHash("sha256").update(JSON.stringify(stable)).digest("hex");
}

function payloadFor(suspects: SuspectsDigest) {
  return {
    week: `${suspects.weekStart} to ${suspects.weekEnd}`,
    lookbackHours: suspects.windowHours,
    flares: suspects.flares,
    mealsEvaluated: suspects.mealsEvaluated,
    ingredients: suspects.ingredients.map((i) => ({
      name: i.name,
      flareWindowsContaining: i.flaresWithIngredient,
      flareWindowsTotal: i.flaresTotal,
      averageHoursBeforeFlare: i.avgOnsetHours,
      timesEatenThisWeek: i.timesLoggedThisWeek,
    })),
    timingWindows: suspects.timingWindows,
  };
}

let client: Anthropic | null = null;
function anthropic(): Anthropic | null {
  if (!process.env.ANTHROPIC_API_KEY) return null;
  client ??= new Anthropic({ timeout: REQUEST_TIMEOUT_MS, maxRetries: 1 });
  return client;
}

async function generateWithClaude(suspects: SuspectsDigest): Promise<string | null> {
  const api = anthropic();
  if (!api) return null;
  try {
    const response = await api.beta.messages.create({
      model: SYNTHESIS_MODEL,
      max_tokens: 600,
      output_config: { effort: "low" },
      betas: ["server-side-fallback-2026-06-01"],
      fallbacks: [{ model: "claude-opus-4-8" }],
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: JSON.stringify(payloadFor(suspects)) }],
    });
    if (response.stop_reason === "refusal") return null;
    const text = response.content.filter((b) => b.type === "text").map((b) => b.text).join("").trim();
    return text || null;
  } catch (error) {
    if (error instanceof Anthropic.APIError) {
      console.error(`Synthesis API error ${error.status}: ${error.message}`);
    } else {
      console.error("Synthesis error:", error);
    }
    return null;
  }
}

/**
 * Returns the cached synthesis when the suspects data hasn't changed,
 * otherwise generates one (Claude when configured, rules otherwise).
 */
export async function synthesize(userId: string, suspects: SuspectsDigest, symptomFilter: string | null): Promise<SynthesisResult> {
  const kind = "suspects_weekly";
  const filter = symptomFilter ?? "";
  const inputHash = hashInput(suspects);
  const fallback = rulesSynthesis(suspects);

  const cached = await storage.getSynthesis(userId, kind, suspects.weekStart, filter);
  if (cached && cached.inputHash === inputHash) {
    return { text: cached.text, source: cached.source as "claude" | "rules", model: cached.model, cached: true, generatedAt: cached.createdAt ?? new Date(), suggestedWatchlist: fallback.suggestedWatchlist };
  }

  const now = Date.now();
  const recentlyGenerated = now - (lastGeneration.get(userId) ?? 0) < RATE_LIMIT_MS;
  let text: string | null = null;
  if (suspects.flares > 0 && suspects.ingredients.length > 0 && !recentlyGenerated) {
    lastGeneration.set(userId, now);
    text = await generateWithClaude(suspects);
  }

  const source: "claude" | "rules" = text ? "claude" : "rules";
  const finalText = text ?? fallback.text;
  const saved = await storage.upsertSynthesis({ userId, kind, weekStart: suspects.weekStart, symptomFilter: filter, inputHash, source, model: text ? SYNTHESIS_MODEL : null, text: finalText });
  return { text: finalText, source, model: saved.model, cached: false, generatedAt: saved.createdAt ?? new Date(), suggestedWatchlist: fallback.suggestedWatchlist };
}
