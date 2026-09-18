import type { Express, Request, Response } from "express";
import { storage } from "../storage";
import { isAuthenticated } from "../auth";
import { computeWeeklyDigest } from "../analytics/digest";
import { computeSuspects } from "../analytics/suspects";
import { addDays, isIsoDate, localDate } from "../analytics/time";
import { resolveTimezone } from "./context";

async function history(userId: string) {
  const [meals, symptoms, correlations, settings] = await Promise.all([
    storage.getMealsByUser(userId),
    storage.getSymptomsByUser(userId),
    storage.getAllCorrelationsByUser(userId),
    storage.getSettings(userId),
  ]);
  return { meals, symptoms, correlations, settings };
}

function weekStartParam(req: Request, tz: string): string | null {
  const raw = req.query.weekStart;
  if (raw === undefined || raw === "") return addDays(localDate(new Date(), tz), -6);
  return typeof raw === "string" && isIsoDate(raw) ? raw : null;
}

export function registerDigestRoutes(app: Express) {
  app.get("/api/digest/weekly", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const tz = await resolveTimezone(req);
      const weekStart = weekStartParam(req, tz);
      if (!weekStart) return res.status(400).json({ message: "weekStart must be YYYY-MM-DD" });

      const { meals, symptoms, correlations, settings } = await history(req.user!.id);
      res.json(computeWeeklyDigest(meals, symptoms, correlations, weekStart, tz, settings, localDate(new Date(), tz)));
    } catch (error) {
      console.error("Error computing weekly digest:", error);
      res.status(500).json({ message: "Failed to compute digest" });
    }
  });

  app.get("/api/digest/suspects", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const tz = await resolveTimezone(req);
      const weekStart = weekStartParam(req, tz);
      if (!weekStart) return res.status(400).json({ message: "weekStart must be YYYY-MM-DD" });
      const symptom = typeof req.query.symptom === "string" && req.query.symptom && req.query.symptom !== "All Symptoms" ? req.query.symptom : null;

      const { meals, symptoms, correlations, settings } = await history(req.user!.id);
      const watchlist = (await storage.getWatchlist(req.user!.id)).map((w) => w.ingredient);
      res.json(computeSuspects(meals, symptoms, correlations, watchlist, weekStart, tz, settings.correlationWindowHours, symptom));
    } catch (error) {
      console.error("Error computing suspects:", error);
      res.status(500).json({ message: "Failed to compute suspects" });
    }
  });
}
