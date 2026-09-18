import type { Request, Response } from "express";
import { z } from "zod";
import { storage } from "../storage";
import { isValidTimezone, parseInstant } from "../analytics/time";

// The timezone an entry was logged in: explicit `tz` on the request wins,
// then the user's saved setting.
export async function resolveTimezone(req: Request): Promise<string> {
  const requested = (req.body?.tz ?? req.query?.tz) as unknown;
  if (typeof requested === "string" && isValidTimezone(requested)) return requested;
  const settings = await storage.getSettings(req.user!.id);
  return settings.timezone;
}

export function parseId(value: string): number | null {
  const id = parseInt(value, 10);
  return Number.isNaN(id) ? null : id;
}

// Converts a body `timestamp` (ISO string) into a Date in place. Returns an
// error message when the value is present but not a valid instant.
export function coerceTimestamp(body: Record<string, unknown>): string | null {
  if (body.timestamp === undefined || body.timestamp === null) return null;
  const parsed = parseInstant(body.timestamp);
  if (!parsed) return "Invalid timestamp format";
  body.timestamp = parsed;
  return null;
}

export function sendZodError(res: Response, message: string, error: z.ZodError) {
  res.status(400).json({ message, errors: error.errors });
}
