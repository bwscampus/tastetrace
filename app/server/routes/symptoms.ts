import type { Express, Request, Response } from "express";
import { z } from "zod";
import { storage } from "../storage";
import { isAuthenticated } from "../auth";
import { insertSymptomSchema, updateSymptomSchema, insertCustomSymptomSchema, Symptom } from "@shared/schema";
import { SYMPTOM_CATALOG, catalogItemByKey } from "@shared/symptomCatalog";
import { resolveTimezone, parseId, coerceTimestamp, sendZodError } from "./context";

const batchSchema = z.object({
  timestamp: z.date().optional(),
  durationMinutes: z.number().int().min(0).max(60 * 24 * 7).optional().nullable(),
  notes: z.string().max(2000).optional().nullable(),
  items: z.array(z.object({
    name: z.string().trim().min(1).max(80),
    catalogKey: z.string().max(80).optional().nullable(),
    intensity: z.number().int().min(1).max(5),
  })).min(1).max(20),
});

// Adds the catalog presentation (emoji, body region) to a stored symptom
export function presentSymptom(symptom: Symptom, custom: { key: string; emoji: string; bodyRegion: string | null }[] = []) {
  const item = catalogItemByKey(symptom.catalogKey) ?? custom.find((c) => c.key === symptom.catalogKey);
  return { ...symptom, emoji: item?.emoji ?? null, bodyRegion: item?.bodyRegion ?? null };
}

export function registerSymptomRoutes(app: Express) {
  app.get("/api/symptoms", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const symptoms = await storage.getSymptomsByUser(req.user!.id);
      res.json(symptoms);
    } catch (error) {
      console.error("Error getting symptoms:", error);
      res.status(500).json({ message: "Failed to get symptoms" });
    }
  });

  app.post("/api/symptoms", isAuthenticated, async (req: Request, res: Response) => {
    const userId = req.user!.id;
    
    try {
      const symptomData = { ...req.body, userId };
      const timestampError = coerceTimestamp(symptomData);
      if (timestampError) return res.status(400).json({ message: timestampError });

      const validatedData = insertSymptomSchema.parse(symptomData);
      const symptom = await storage.createSymptom(validatedData, await resolveTimezone(req));
      res.status(201).json(presentSymptom(symptom));
    } catch (error) {
      if (error instanceof z.ZodError) {
        sendZodError(res, "Invalid symptom data", error);
      } else {
        console.error("Error creating symptom:", error);
        res.status(500).json({ message: "Failed to create symptom" });
      }
    }
  });

  // Several symptoms logged at once from the Quick Log grid
  app.post("/api/symptoms/batch", isAuthenticated, async (req: Request, res: Response) => {
    const userId = req.user!.id;

    try {
      const body = { ...req.body };
      const timestampError = coerceTimestamp(body);
      if (timestampError) return res.status(400).json({ message: timestampError });

      const batch = batchSchema.parse(body);
      const tz = await resolveTimezone(req);
      const created = await storage.createSymptoms(
        batch.items.map((item) => ({
          userId,
          name: item.name,
          catalogKey: item.catalogKey ?? undefined,
          intensity: item.intensity,
          timestamp: batch.timestamp,
          durationMinutes: batch.durationMinutes ?? undefined,
          notes: batch.notes ?? undefined,
        })),
        tz,
      );
      const custom = await storage.getCustomSymptoms(userId);
      res.status(201).json(created.map((s) => presentSymptom(s, custom)));
    } catch (error) {
      if (error instanceof z.ZodError) {
        sendZodError(res, "Invalid symptom data", error);
      } else {
        console.error("Error creating symptoms:", error);
        res.status(500).json({ message: "Failed to create symptoms" });
      }
    }
  });

  app.get("/api/symptoms/:id", isAuthenticated, async (req: Request, res: Response) => {
    const id = parseId(req.params.id);
    if (id === null) return res.status(400).json({ message: "Invalid symptom ID" });

    try {
      const symptom = await storage.getSymptom(id, req.user!.id);
      if (!symptom) return res.status(404).json({ message: "Symptom not found" });
      res.json(symptom);
    } catch (error) {
      console.error("Error getting symptom:", error);
      res.status(500).json({ message: "Failed to get symptom" });
    }
  });

  app.put("/api/symptoms/:id", isAuthenticated, async (req: Request, res: Response) => {
    const id = parseId(req.params.id);
    if (id === null) return res.status(400).json({ message: "Invalid symptom ID" });

    try {
      const updateData = { ...req.body };
      const timestampError = coerceTimestamp(updateData);
      if (timestampError) return res.status(400).json({ message: timestampError });

      const validated = updateSymptomSchema.parse(updateData);
      const updatedSymptom = await storage.updateSymptom(id, req.user!.id, validated, await resolveTimezone(req));
      if (!updatedSymptom) return res.status(404).json({ message: "Symptom not found" });
      res.json(updatedSymptom);
    } catch (error) {
      if (error instanceof z.ZodError) {
        sendZodError(res, "Invalid symptom data", error);
      } else {
        console.error("Error updating symptom:", error);
        res.status(500).json({ message: "Failed to update symptom" });
      }
    }
  });

  app.delete("/api/symptoms/:id", isAuthenticated, async (req: Request, res: Response) => {
    const id = parseId(req.params.id);
    if (id === null) return res.status(400).json({ message: "Invalid symptom ID" });

    try {
      const deleted = await storage.deleteSymptom(id, req.user!.id);
      if (!deleted) return res.status(404).json({ message: "Symptom not found" });
      res.status(204).end();
    } catch (error) {
      console.error("Error deleting symptom:", error);
      res.status(500).json({ message: "Failed to delete symptom" });
    }
  });

  // Symptom catalog: the built-in grid plus the user's custom symptoms
  app.get("/api/symptom-catalog", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const custom = await storage.getCustomSymptoms(req.user!.id);
      res.json({ defaults: SYMPTOM_CATALOG, custom });
    } catch (error) {
      console.error("Error getting symptom catalog:", error);
      res.status(500).json({ message: "Failed to get symptom catalog" });
    }
  });

  app.post("/api/symptom-catalog", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const data = insertCustomSymptomSchema.parse(req.body);
      const created = await storage.createCustomSymptom(req.user!.id, data);
      res.status(201).json(created);
    } catch (error) {
      if (error instanceof z.ZodError) {
        sendZodError(res, "Invalid symptom", error);
      } else {
        console.error("Error creating custom symptom:", error);
        res.status(500).json({ message: "Failed to create symptom" });
      }
    }
  });

  app.delete("/api/symptom-catalog/:id", isAuthenticated, async (req: Request, res: Response) => {
    const id = parseId(req.params.id);
    if (id === null) return res.status(400).json({ message: "Invalid symptom ID" });

    try {
      const deleted = await storage.deleteCustomSymptom(id, req.user!.id);
      if (!deleted) return res.status(404).json({ message: "Symptom not found" });
      res.status(204).end();
    } catch (error) {
      console.error("Error deleting custom symptom:", error);
      res.status(500).json({ message: "Failed to delete symptom" });
    }
  });
}
