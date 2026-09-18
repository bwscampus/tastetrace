import type { Express, Request, Response } from "express";
import { z } from "zod";
import { storage } from "../storage";
import { isAuthenticated } from "../auth";
import { insertDishSchema, ingredientDetailSchema, MealType } from "@shared/schema";
import { resolveTimezone, parseId, coerceTimestamp, sendZodError } from "./context";

const logDishSchema = z.object({
  mealType: z.nativeEnum(MealType),
  timestamp: z.date().optional(),
  notes: z.string().max(2000).optional().nullable(),
  overrides: z.object({
    ingredientDetails: z.array(ingredientDetailSchema).optional(),
  }).optional(),
});

// Saved dish tiles: one-tap meal logging with remembered ingredients
export function registerDishRoutes(app: Express) {
  app.get("/api/dishes", isAuthenticated, async (req: Request, res: Response) => {
    try {
      res.json(await storage.getDishes(req.user!.id));
    } catch (error) {
      console.error("Error getting dishes:", error);
      res.status(500).json({ message: "Failed to get dishes" });
    }
  });

  app.post("/api/dishes", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const dish = insertDishSchema.parse(req.body);
      res.status(201).json(await storage.createDish(req.user!.id, dish));
    } catch (error) {
      if (error instanceof z.ZodError) {
        sendZodError(res, "Invalid dish data", error);
      } else {
        console.error("Error creating dish:", error);
        res.status(500).json({ message: "Failed to create dish" });
      }
    }
  });

  app.put("/api/dishes/:id", isAuthenticated, async (req: Request, res: Response) => {
    const id = parseId(req.params.id);
    if (id === null) return res.status(400).json({ message: "Invalid dish ID" });

    try {
      const patch = insertDishSchema.partial().parse(req.body);
      const updated = await storage.updateDish(id, req.user!.id, patch);
      if (!updated) return res.status(404).json({ message: "Dish not found" });
      res.json(updated);
    } catch (error) {
      if (error instanceof z.ZodError) {
        sendZodError(res, "Invalid dish data", error);
      } else {
        console.error("Error updating dish:", error);
        res.status(500).json({ message: "Failed to update dish" });
      }
    }
  });

  app.delete("/api/dishes/:id", isAuthenticated, async (req: Request, res: Response) => {
    const id = parseId(req.params.id);
    if (id === null) return res.status(400).json({ message: "Invalid dish ID" });

    try {
      const deleted = await storage.deleteDish(id, req.user!.id);
      if (!deleted) return res.status(404).json({ message: "Dish not found" });
      res.status(204).end();
    } catch (error) {
      console.error("Error deleting dish:", error);
      res.status(500).json({ message: "Failed to delete dish" });
    }
  });

  // Logs a meal from the tile, optionally overriding the ingredients this time
  app.post("/api/dishes/:id/log", isAuthenticated, async (req: Request, res: Response) => {
    const id = parseId(req.params.id);
    if (id === null) return res.status(400).json({ message: "Invalid dish ID" });

    try {
      const body = { ...req.body };
      const timestampError = coerceTimestamp(body);
      if (timestampError) return res.status(400).json({ message: timestampError });
      const data = logDishSchema.parse(body);

      const dish = await storage.getDish(id, req.user!.id);
      if (!dish) return res.status(404).json({ message: "Dish not found" });

      const meal = await storage.logDish(dish, {
        mealType: data.mealType,
        timestamp: data.timestamp ?? new Date(),
        notes: data.notes,
        ingredientDetails: data.overrides?.ingredientDetails,
      }, await resolveTimezone(req));
      res.status(201).json(meal);
    } catch (error) {
      if (error instanceof z.ZodError) {
        sendZodError(res, "Invalid meal data", error);
      } else {
        console.error("Error logging dish:", error);
        res.status(500).json({ message: "Failed to log dish" });
      }
    }
  });
}
