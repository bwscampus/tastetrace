import type { Express, Request, Response } from "express";
import { storage } from "../storage";
import { isAuthenticated } from "../auth";
import { addDays, dayBounds, isIsoDate, localDate, localTime } from "../analytics/time";
import { clusterFlares } from "../analytics/flares";
import { suspicionFor, tierFor } from "../analytics/correlations";
import { computeWeeklyDigest } from "../analytics/digest";
import { resolveTimezone } from "./context";
import { publicUser } from "../auth";
import type { IngredientDetail } from "@shared/schema";

function csvCell(value: unknown): string {
  if (value === null || value === undefined) return "";
  const text = String(value);
  return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

async function range(req: Request, tz: string) {
  const to = typeof req.query.to === "string" && req.query.to ? req.query.to : localDate(new Date(), tz);
  const from = typeof req.query.from === "string" && req.query.from ? req.query.from : addDays(to, -29);
  if (!isIsoDate(from) || !isIsoDate(to) || from > to) return null;
  return { from, to, start: dayBounds(from, tz).start, end: new Date(dayBounds(to, tz).end.getTime() - 1) };
}

export function registerExportRoutes(app: Express) {
  // Raw entries as CSV
  app.get("/api/export/csv", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const tz = await resolveTimezone(req);
      const r = await range(req, tz);
      if (!r) return res.status(400).json({ message: "from/to must be YYYY-MM-DD with from <= to" });
      const userId = req.user!.id;
      const [meals, symptoms, dishes] = await Promise.all([
        storage.getMealsByUserAndTimeRange(userId, r.start, r.end),
        storage.getSymptomsByUserAndTimeRange(userId, r.start, r.end),
        storage.getDishes(userId),
      ]);
      const dishName = new Map(dishes.map((d) => [d.id, d.name]));

      const header = ["entry_type", "id", "date", "time", "name", "meal_type", "ingredients", "cook_methods", "dish", "intensity", "severity", "duration_minutes", "notes", "timestamp_utc"];
      const rows: unknown[][] = [];
      for (const m of meals) {
        const details: IngredientDetail[] = m.ingredientDetails ?? (m.ingredients ?? []).map((name) => ({ name }));
        rows.push(["meal", m.id, localDate(m.timestamp, tz), localTime(m.timestamp, tz), m.name, m.mealType,
          details.map((i) => i.name).join("; "), details.map((i) => i.cookMethod ?? "").join("; "),
          m.dishId ? dishName.get(m.dishId) ?? "" : "", "", "", "", m.notes ?? "", m.timestamp.toISOString()]);
      }
      for (const s of symptoms) {
        rows.push(["symptom", s.id, localDate(s.timestamp, tz), localTime(s.timestamp, tz), s.name, "", "", "", "",
          s.intensity ?? "", s.severity, s.durationMinutes ?? "", s.notes ?? "", s.timestamp.toISOString()]);
      }
      rows.sort((a, b) => String(a[13]).localeCompare(String(b[13])));

      const csv = [header, ...rows].map((row) => row.map(csvCell).join(",")).join("\n") + "\n";
      res.setHeader("Content-Type", "text/csv; charset=utf-8");
      res.setHeader("Content-Disposition", `attachment; filename="tastetrace-${r.from}-${r.to}.csv"`);
      res.send(csv);
    } catch (error) {
      console.error("Error exporting CSV:", error);
      res.status(500).json({ message: "Failed to export" });
    }
  });

  // Everything the on-device PDF reports need for a date range
  app.get("/api/export/ledger", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const tz = await resolveTimezone(req);
      const r = await range(req, tz);
      if (!r) return res.status(400).json({ message: "from/to must be YYYY-MM-DD with from <= to" });
      const userId = req.user!.id;
      const [profile, settings, allMeals, allSymptoms, correlations, custom] = await Promise.all([
        storage.getUser(userId), storage.getSettings(userId), storage.getMealsByUser(userId), storage.getSymptomsByUser(userId),
        storage.getAllCorrelationsByUser(userId), storage.getCustomSymptoms(userId),
      ]);
      const meals = allMeals.filter((m) => m.timestamp >= r.start && m.timestamp <= r.end);
      const symptoms = allSymptoms.filter((s) => s.timestamp >= r.start && s.timestamp <= r.end);

      const days: Record<string, { date: string; meals: unknown[]; symptoms: unknown[]; flares: number }> = {};
      const day = (date: string) => (days[date] ??= { date, meals: [], symptoms: [], flares: 0 });
      for (const m of meals) day(localDate(m.timestamp, tz)).meals.push({ ...m, ...suspicionFor(m, allSymptoms, correlations, settings) });
      for (const s of symptoms) day(localDate(s.timestamp, tz)).symptoms.push(s);
      for (const d of Object.values(days)) {
        d.flares = clusterFlares(symptoms.filter((s) => localDate(s.timestamp, tz) === d.date)).length;
      }

      const today = localDate(new Date(), tz);
      const digestWeeks = [];
      for (let weekStart = addDays(r.to, -6); weekStart >= addDays(r.from, -6) && digestWeeks.length < 8; weekStart = addDays(weekStart, -7)) {
        digestWeeks.push(computeWeeklyDigest(allMeals, allSymptoms, correlations, weekStart, tz, settings, today));
      }

      res.json({
        generatedAt: new Date(),
        profile: profile ? { ...publicUser(profile), discoveryPurpose: profile.discoveryPurpose, sensitivityTags: profile.sensitivityTags ?? [] } : null,
        settings,
        range: { from: r.from, to: r.to, tz },
        totals: { meals: meals.length, symptoms: symptoms.length, days: Object.keys(days).length },
        days: Object.values(days).sort((a, b) => a.date.localeCompare(b.date)),
        triggers: correlations.filter((c) => c.confidence >= settings.minConfidence).map((c) => ({ ...c, tier: tierFor(c.confidence) })),
        customSymptoms: custom,
        digestWeeks,
      });
    } catch (error) {
      console.error("Error exporting ledger:", error);
      res.status(500).json({ message: "Failed to export" });
    }
  });
}
