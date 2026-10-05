import type { Express, Request, Response } from "express";
import { z } from "zod";
import { storage } from "../storage";
import { pool } from "../db";
import { setupAuth } from "../auth";
import { createWaitlistLimiter } from "../rateLimit";
import { registerMealRoutes } from "./meals";
import { registerSymptomRoutes } from "./symptoms";
import { registerEntryRoutes } from "./entries";
import { registerProfileRoutes } from "./profile";
import { registerDishRoutes } from "./dishes";
import { registerCoverageRoutes } from "./coverage";
import { registerDigestRoutes } from "./digest";
import { registerInsightRoutes } from "./insights";
import { registerWatchlistRoutes } from "./watchlist";
import { registerAiRoutes } from "./ai";
import { registerExportRoutes } from "./export";

// Origins allowed to post to the waitlist endpoint (the landing site)
const WAITLIST_ORIGINS = (process.env.WAITLIST_ORIGINS ||
  "https://tastetrace.up.railway.app,https://tastetrace.app,https://www.tastetrace.app")
  .split(",")
  .map((origin) => origin.trim());

const waitlistSchema = z.object({
  email: z.string().trim().toLowerCase().email().max(254),
  company: z.string().optional(), // honeypot, left empty by real visitors
});

export function registerRoutes(app: Express): void {
  // Railway's health check (API-9): proves the app can reach its database.
  // Answers only {status}; never versions, hosts or error details.
  app.get("/api/health", async (_req: Request, res: Response) => {
    try {
      await pool.query("select 1");
      res.json({ status: "ok" });
    } catch {
      res.status(503).json({ status: "unavailable" });
    }
  });

  // Waitlist signups come cross-origin from the landing page, so this is
  // registered before the session middleware and answers CORS itself.
  app.use("/api/waitlist", (req: Request, res: Response, next) => {
    const origin = req.headers.origin;
    if (origin && WAITLIST_ORIGINS.includes(origin)) {
      res.setHeader("Access-Control-Allow-Origin", origin);
      res.setHeader("Vary", "Origin");
      res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
      res.setHeader("Access-Control-Allow-Headers", "Content-Type");
    }
    if (req.method === "OPTIONS") return res.sendStatus(204);
    next();
  });

  app.post("/api/waitlist", createWaitlistLimiter(), async (req: Request, res: Response) => {
    const parsed = waitlistSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ message: "Enter a valid email address" });
    }

    try {
      if (!parsed.data.company) {
        await storage.addWaitlistSignup(parsed.data.email);
      }
      res.status(201).json({ message: "You're on the list" });
    } catch (error) {
      console.error("Error adding waitlist signup:", error);
      res.status(500).json({ message: "Could not join the waitlist" });
    }
  });

  // Cookie sessions for the web client (the iOS app uses the Python API)
  setupAuth(app);

  // Password reset is not built for web accounts yet (the iOS app's API has
  // its own, separate accounts). Say so honestly instead of claiming an email
  // was sent (FE-6). The reply never depends on the address, so it can't be
  // used to check who has an account, and the address is never logged (API-8).
  app.post("/api/forgot-password", (_req: Request, res: Response) => {
    res.status(200).json({
      message:
        "Password reset by email isn't available on the web yet. Contact the TasteTrace team and we'll help you get back into your account.",
    });
  });

  registerProfileRoutes(app);
  registerMealRoutes(app);
  registerDishRoutes(app);
  registerSymptomRoutes(app);
  registerEntryRoutes(app);
  registerCoverageRoutes(app);
  registerDigestRoutes(app);
  registerInsightRoutes(app);
  registerWatchlistRoutes(app);
  registerAiRoutes(app);
  registerExportRoutes(app);
}
