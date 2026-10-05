import type { Request } from "express";
import { rateLimit, ipKeyGenerator, type RateLimitRequestHandler } from "express-rate-limit";

// Railway's edge overwrites X-Real-IP on every request, so it is the one
// client-IP header a caller cannot forge. Fall back to req.ip locally.
export function clientIp(req: Request): string {
  return req.get("x-real-ip")?.trim() || req.ip || "unknown";
}

// In-memory, per instance: enough to stop password guessing from one IP.
// Move to a shared store (Redis) if the app ever runs more than one replica.
function limiter(windowMs: number, limit: number, message: string): RateLimitRequestHandler {
  return rateLimit({
    windowMs,
    limit,
    standardHeaders: "draft-7",
    legacyHeaders: false,
    keyGenerator: (req) => ipKeyGenerator(clientIp(req)),
    message: { message },
  });
}

// Login and register: 10 attempts per 15 minutes per IP (AUTH-3)
export const createAuthLimiter = () =>
  limiter(15 * 60 * 1000, 10, "Too many attempts. Please wait a few minutes and try again.");

// Waitlist: public and unauthenticated, so cap it to stop list stuffing
export const createWaitlistLimiter = () =>
  limiter(60 * 60 * 1000, 20, "Too many signups from this network. Please try again later.");
