import type { Express, Request, Response } from "express";
import { z } from "zod";
import { storage } from "../storage";
import { isAuthenticated } from "../auth";
import { computeSuspects } from "../analytics/suspects";
import { synthesize } from "../ai/synthesis";
import { addDays, isIsoDate, localDate } from "../analytics/time";
import { resolveTimezone, sendZodError } from "./context";

const bodySchema = z.object({
  weekStart: z.string().optional(),
  symptom: z.string().max(80).optional().nullable(),
  tz: z.string().optional(),
});

export function registerAiRoutes(app: Express) {
  // AI Pattern Synthesis for the Food Suspect Digest
  app.post("/api/ai/synthesis", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const body = bodySchema.parse(req.body ?? {});
      const tz = await resolveTimezone(req);
      const weekStart = body.weekStart || addDays(localDate(new Date(), tz), -6);
      if (!isIsoDate(weekStart)) return res.status(400).json({ message: "weekStart must be YYYY-MM-DD" });
      const symptom = body.symptom && body.symptom !== "All Symptoms" ? body.symptom : null;

      const userId = req.user!.id;
      const [meals, symptoms, correlations, settings, watchlist] = await Promise.all([
        storage.getMealsByUser(userId),
        storage.getSymptomsByUser(userId),
        storage.getAllCorrelationsByUser(userId),
        storage.getSettings(userId),
        storage.getWatchlist(userId),
      ]);
      const suspects = computeSuspects(meals, symptoms, correlations, watchlist.map((w) => w.ingredient), weekStart, tz, settings.correlationWindowHours, symptom);
      res.json(await synthesize(userId, suspects, symptom));
    } catch (error) {
      if (error instanceof z.ZodError) {
        sendZodError(res, "Invalid request", error);
      } else {
        console.error("Error generating synthesis:", error);
        res.status(500).json({ message: "Failed to generate synthesis" });
      }
    }
  });
}
