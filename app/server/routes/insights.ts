import type { Express, Request, Response } from "express";
import { storage } from "../storage";
import { isAuthenticated } from "../auth";
import { tierFor } from "../analytics/correlations";
import { hoursBetween } from "../analytics/flares";
import { mealItems, normalizeItem } from "../analytics/foods";
import { catalogItemByKey, catalogItemByName } from "@shared/symptomCatalog";

const DIMENSIONS = ["ingredient", "cook_method", "food"] as const;

export function registerInsightRoutes(app: Express) {
  // Trigger Insights: symptom-specific confidence per ingredient or cooking style
  app.get("/api/insights/triggers", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const dimension = (DIMENSIONS as readonly string[]).includes(String(req.query.dimension)) ? String(req.query.dimension) : "ingredient";
      const symptom = typeof req.query.symptom === "string" && req.query.symptom ? req.query.symptom : null;
      const settings = await storage.getSettings(req.user!.id);
      const minConfidence = req.query.minConfidence !== undefined ? Number(req.query.minConfidence) : settings.minConfidence;
      if (Number.isNaN(minConfidence) || minConfidence < 0 || minConfidence > 100) {
        return res.status(400).json({ message: "minConfidence must be 0-100" });
      }

      const [rows, meals, symptoms, custom] = await Promise.all([
        storage.getAllCorrelationsByUser(req.user!.id),
        storage.getMealsByUser(req.user!.id),
        storage.getSymptomsByUser(req.user!.id),
        storage.getCustomSymptoms(req.user!.id),
      ]);

      const counts = new Map<string, { key: string | null; count: number }>();
      for (const s of symptoms) {
        const entry = counts.get(s.name) ?? { key: s.catalogKey, count: 0 };
        entry.count++;
        counts.set(s.name, entry);
      }
      const symptomList = [...counts.entries()].map(([name, { key, count }]) => {
        const item = catalogItemByKey(key) ?? catalogItemByName(name) ?? custom.find((c) => c.key === key);
        return { name, emoji: item?.emoji ?? "⚡️", count };
      }).sort((a, b) => b.count - a.count);

      const matching = rows.filter((r) => r.dimension === dimension && (!symptom || r.symptomName === symptom));
      const visible = matching.filter((r) => r.confidence >= minConfidence);

      const cards = visible.map((row) => {
        const key = normalizeItem(row.foodName);
        const evidence = meals
          .filter((m) => mealItems(m).some((i) => i.dimension === dimension && i.key === key))
          .flatMap((m) => symptoms
            .filter((s) => s.name === row.symptomName)
            .map((s) => ({ meal: m, symptom: s, onset: hoursBetween(m.timestamp, s.timestamp) }))
            .filter((p) => p.onset > 0 && p.onset <= (row.windowHours ?? settings.correlationWindowHours)))
          .sort((a, b) => b.symptom.timestamp.getTime() - a.symptom.timestamp.getTime())
          .slice(0, 5)
          .map((p) => ({ mealId: p.meal.id, mealName: p.meal.name, mealAt: p.meal.timestamp, symptomAt: p.symptom.timestamp, onsetHours: Math.round(p.onset * 10) / 10 }));
        return {
          item: row.foodName,
          dimension: row.dimension,
          symptomName: row.symptomName,
          confidence: row.confidence,
          tier: tierFor(row.confidence),
          exposures: row.exposures,
          flareExposures: row.flareExposures,
          hitRate: row.exposures ? Math.round(row.flareExposures / row.exposures * 100) / 100 : 0,
          baselineRate: row.baselineRate,
          lift: row.lift,
          avgOnsetHours: row.avgOnsetHours,
          lastFlareAt: row.lastFlareAt,
          evidence,
        };
      });

      res.json({
        dimension,
        minConfidence,
        windowHours: settings.correlationWindowHours,
        symptoms: symptomList,
        cards,
        hiddenBelowThreshold: matching.length - visible.length,
      });
    } catch (error) {
      console.error("Error computing trigger insights:", error);
      res.status(500).json({ message: "Failed to compute insights" });
    }
  });
}
