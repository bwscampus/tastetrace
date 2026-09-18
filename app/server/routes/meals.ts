import type { Express, Request, Response } from "express";
import { z } from "zod";
import { storage } from "../storage";
import { isAuthenticated } from "../auth";
import { insertMealSchema, updateMealSchema } from "@shared/schema";
import { resolveTimezone, parseId, coerceTimestamp, sendZodError } from "./context";

export function registerMealRoutes(app: Express) {
  app.get("/api/meals", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const meals = await storage.getMealsByUser(req.user!.id);
      res.json(meals);
    } catch (error) {
      console.error("Error getting meals:", error);
      res.status(500).json({ message: "Failed to get meals" });
    }
  });

  app.post("/api/meals", isAuthenticated, async (req: Request, res: Response) => {
    const userId = req.user!.id;
    
    try {
      const mealData = { ...req.body, userId };
      const timestampError = coerceTimestamp(mealData);
      if (timestampError) return res.status(400).json({ message: timestampError });
      
      const validatedData = insertMealSchema.parse(mealData);
      const meal = await storage.createMeal(validatedData, await resolveTimezone(req));
      res.status(201).json(meal);
    } catch (error) {
      if (error instanceof z.ZodError) {
        sendZodError(res, "Invalid meal data", error);
      } else {
        console.error("Error creating meal:", error);
        res.status(500).json({ message: "Failed to create meal" });
      }
    }
  });

  app.get("/api/meals/:id", isAuthenticated, async (req: Request, res: Response) => {
    const id = parseId(req.params.id);
    if (id === null) return res.status(400).json({ message: "Invalid meal ID" });

    try {
      const meal = await storage.getMeal(id, req.user!.id);
      if (!meal) return res.status(404).json({ message: "Meal not found" });
      res.json(meal);
    } catch (error) {
      console.error("Error getting meal:", error);
      res.status(500).json({ message: "Failed to get meal" });
    }
  });

  app.put("/api/meals/:id", isAuthenticated, async (req: Request, res: Response) => {
    const id = parseId(req.params.id);
    if (id === null) return res.status(400).json({ message: "Invalid meal ID" });

    try {
      const updateData = { ...req.body };
      const timestampError = coerceTimestamp(updateData);
      if (timestampError) return res.status(400).json({ message: timestampError });

      const validated = updateMealSchema.parse(updateData);
      const updatedMeal = await storage.updateMeal(id, req.user!.id, validated, await resolveTimezone(req));
      if (!updatedMeal) return res.status(404).json({ message: "Meal not found" });
      res.json(updatedMeal);
    } catch (error) {
      if (error instanceof z.ZodError) {
        sendZodError(res, "Invalid meal data", error);
      } else {
        console.error("Error updating meal:", error);
        res.status(500).json({ message: "Failed to update meal" });
      }
    }
  });

  app.delete("/api/meals/:id", isAuthenticated, async (req: Request, res: Response) => {
    const id = parseId(req.params.id);
    if (id === null) return res.status(400).json({ message: "Invalid meal ID" });

    try {
      const deleted = await storage.deleteMeal(id, req.user!.id);
      if (!deleted) return res.status(404).json({ message: "Meal not found" });
      res.status(204).end();
    } catch (error) {
      console.error("Error deleting meal:", error);
      res.status(500).json({ message: "Failed to delete meal" });
    }
  });
}
