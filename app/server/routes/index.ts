import type { Express, Request, Response } from "express";
import { z } from "zod";
import { storage } from "../storage";
import { setupAuth } from "../auth";
import { registerTokenRoutes } from "../tokenAuth";
import { registerMealRoutes } from "./meals";
import { registerSymptomRoutes } from "./symptoms";
import { registerEntryRoutes } from "./entries";
import { registerProfileRoutes } from "./profile";

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

  app.post("/api/waitlist", async (req: Request, res: Response) => {
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

  // Cookie sessions (web) and bearer tokens (mobile) both end up as req.user
  setupAuth(app);
  registerTokenRoutes(app);

  // Forgot password endpoint
  app.post('/api/forgot-password', async (req: Request, res: Response) => {
    try {
      const { email } = req.body;
      
      if (!email) {
        return res.status(400).json({ message: "Email is required" });
      }

      // Check if user exists
      const user = await storage.getUserByEmail(email);
      if (!user) {
        // Don't reveal if user exists or not for security
        return res.status(200).json({ message: "If an account with that email exists, a password reset link has been sent." });
      }

      // In a real application, you would:
      // 1. Generate a secure reset token
      // 2. Store it in the database with an expiration time
      // 3. Send an email with the reset link
      // 
      // For this demo, we'll just return a success message
      console.log(`Password reset requested for: ${email}`);
      
      res.status(200).json({ 
        message: "If an account with that email exists, a password reset link has been sent." 
      });
    } catch (error) {
      console.error("Error processing forgot password:", error);
      res.status(500).json({ message: "Internal server error" });
    }
  });

  registerProfileRoutes(app);
  registerMealRoutes(app);
  registerSymptomRoutes(app);
  registerEntryRoutes(app);
}
