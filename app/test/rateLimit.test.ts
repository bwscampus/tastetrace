import { describe, it, expect } from "vitest";
import express from "express";
import request from "supertest";
import { createAuthLimiter, createWaitlistLimiter } from "../server/rateLimit";

// The limiters on their own, so these run without a database (AUTH-3)
function appWith(limiter: express.RequestHandler) {
  const app = express();
  app.set("trust proxy", 1);
  app.post("/attempt", limiter, (_req, res) => res.sendStatus(401));
  return app;
}

describe("auth rate limiter", () => {
  it("returns 429 on the 11th attempt from one IP", async () => {
    const app = appWith(createAuthLimiter());
    const statuses: number[] = [];
    for (let i = 0; i < 11; i++) {
      statuses.push((await request(app).post("/attempt").set("X-Real-IP", "203.0.113.5")).status);
    }
    expect(statuses.slice(0, 10).every((s) => s === 401)).toBe(true);
    expect(statuses[10]).toBe(429);
  });

  it("keys on X-Real-IP, so a rotating X-Forwarded-For does not reset it", async () => {
    const app = appWith(createAuthLimiter());
    let last = 0;
    for (let i = 0; i < 11; i++) {
      last = (
        await request(app)
          .post("/attempt")
          .set("X-Real-IP", "203.0.113.6")
          .set("X-Forwarded-For", `10.0.0.${i}`)
      ).status;
    }
    expect(last).toBe(429);
  });

  it("counts different clients separately", async () => {
    const app = appWith(createAuthLimiter());
    for (let i = 0; i < 10; i++) {
      await request(app).post("/attempt").set("X-Real-IP", "203.0.113.7");
    }
    const other = await request(app).post("/attempt").set("X-Real-IP", "203.0.113.8");
    expect(other.status).toBe(401);
  });

  it("limits the public waitlist too", async () => {
    const app = appWith(createWaitlistLimiter());
    let last = 0;
    for (let i = 0; i < 21; i++) {
      last = (await request(app).post("/attempt").set("X-Real-IP", "203.0.113.9")).status;
    }
    expect(last).toBe(429);
  });
});
