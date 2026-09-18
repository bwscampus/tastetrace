import type { Express, Request, Response } from "express";
import { z } from "zod";
import { storage } from "../storage";
import { isAuthenticated } from "../auth";
import { normalizeItem } from "../analytics/foods";
import { parseId, sendZodError } from "./context";

const addSchema = z.object({
  ingredient: z.string().trim().min(1).max(100),
  source: z.enum(["manual", "suspect", "synthesis"]).default("manual"),
});

export function registerWatchlistRoutes(app: Express) {
  app.get("/api/watchlist", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const [items, correlations] = await Promise.all([
        storage.getWatchlist(req.user!.id),
        storage.getAllCorrelationsByUser(req.user!.id),
      ]);
      res.json(items.map((item) => ({
        ...item,
        confidenceMax: Math.max(0, ...correlations.filter((c) => normalizeItem(c.foodName) === item.ingredient).map((c) => c.confidence)),
      })));
    } catch (error) {
      console.error("Error getting watchlist:", error);
      res.status(500).json({ message: "Failed to get watchlist" });
    }
  });

  app.post("/api/watchlist", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const { ingredient, source } = addSchema.parse(req.body);
      res.status(201).json(await storage.addWatchlistItem(req.user!.id, ingredient, source));
    } catch (error) {
      if (error instanceof z.ZodError) {
        sendZodError(res, "Invalid watchlist item", error);
      } else {
        console.error("Error adding to watchlist:", error);
        res.status(500).json({ message: "Failed to add to watchlist" });
      }
    }
  });

  app.delete("/api/watchlist/:id", isAuthenticated, async (req: Request, res: Response) => {
    const id = parseId(req.params.id);
    if (id === null) return res.status(400).json({ message: "Invalid watchlist ID" });
    try {
      const removed = await storage.removeWatchlistItem(id, req.user!.id);
      if (!removed) return res.status(404).json({ message: "Watchlist item not found" });
      res.status(204).end();
    } catch (error) {
      console.error("Error removing from watchlist:", error);
      res.status(500).json({ message: "Failed to remove from watchlist" });
    }
  });
}
