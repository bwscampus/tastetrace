import type { Express, Request, Response } from "express";
import { z } from "zod";
import { storage } from "../storage";
import { isAuthenticated, publicUser } from "../auth";
import { profilePatchSchema, settingsPatchSchema, User } from "@shared/schema";
import { isValidTimezone } from "../analytics/time";
import { requestRecompute } from "../analytics/scheduler";
import { sendZodError } from "./context";

async function presentProfile(user: User) {
  const firstLogAt = await storage.getFirstEntryAt(user.id);
  const since = firstLogAt ?? user.createdAt ?? new Date();
  const journalerDays = Math.max(1, Math.floor((Date.now() - since.getTime()) / 86_400_000) + 1);
  return {
    ...publicUser(user),
    discoveryPurpose: user.discoveryPurpose,
    sensitivityTags: user.sensitivityTags ?? [],
    journalerDays,
    firstLogAt: firstLogAt ?? null,
  };
}

export function registerProfileRoutes(app: Express) {
  app.get("/api/profile", isAuthenticated, async (req: Request, res: Response) => {
    try {
      res.json(await presentProfile(req.user!));
    } catch (error) {
      console.error("Error getting profile:", error);
      res.status(500).json({ message: "Failed to get profile" });
    }
  });

  app.patch("/api/profile", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const patch = profilePatchSchema.parse(req.body);
      const user = await storage.updateUserProfile(req.user!.id, patch);
      if (!user) return res.status(404).json({ message: "User not found" });
      res.json(await presentProfile(user));
    } catch (error) {
      if (error instanceof z.ZodError) {
        sendZodError(res, "Invalid profile data", error);
      } else {
        console.error("Error updating profile:", error);
        res.status(500).json({ message: "Failed to update profile" });
      }
    }
  });

  app.get("/api/settings", isAuthenticated, async (req: Request, res: Response) => {
    try {
      res.json(await storage.getSettings(req.user!.id));
    } catch (error) {
      console.error("Error getting settings:", error);
      res.status(500).json({ message: "Failed to get settings" });
    }
  });

  app.patch("/api/settings", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const patch = settingsPatchSchema.parse(req.body);
      if (patch.timezone && !isValidTimezone(patch.timezone)) {
        return res.status(400).json({ message: "Unknown timezone" });
      }
      const settings = await storage.updateSettings(req.user!.id, patch);
      if (patch.correlationWindowHours !== undefined || patch.minTriggerCount !== undefined) {
        requestRecompute(req.user!.id);
      }
      res.json(settings);
    } catch (error) {
      if (error instanceof z.ZodError) {
        sendZodError(res, "Invalid settings", error);
      } else {
        console.error("Error updating settings:", error);
        res.status(500).json({ message: "Failed to update settings" });
      }
    }
  });
}
