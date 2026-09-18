import type { Express, Request, Response } from "express";
import { storage } from "../storage";
import { isAuthenticated } from "../auth";
import { computeCoverage } from "../analytics/coverage";
import { addDays, dayBounds, isIsoDate, localDate } from "../analytics/time";
import { resolveTimezone } from "./context";

// How far back to look when counting a streak
const STREAK_LOOKBACK_DAYS = 365;

export function registerCoverageRoutes(app: Express) {
  app.get("/api/coverage", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const tz = await resolveTimezone(req);
      const date = typeof req.query.date === "string" && req.query.date ? req.query.date : localDate(new Date(), tz);
      if (!isIsoDate(date)) return res.status(400).json({ message: "Date must be YYYY-MM-DD" });

      const settings = await storage.getSettings(req.user!.id);
      const start = dayBounds(addDays(date, -STREAK_LOOKBACK_DAYS), tz).start;
      const end = dayBounds(date, tz).end;
      const meals = await storage.getMealsByUserAndTimeRange(req.user!.id, start, end);
      res.json(computeCoverage(meals, date, tz, settings));
    } catch (error) {
      console.error("Error computing coverage:", error);
      res.status(500).json({ message: "Failed to compute coverage" });
    }
  });
}
