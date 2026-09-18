import type { Express, Request, Response, NextFunction } from "express";
import { createHash, randomBytes } from "crypto";
import { z } from "zod";
import { storage } from "./storage";
import { hashPassword, comparePasswords, publicUser } from "./auth";

// Bearer tokens let the mobile app authenticate without cookies. A token is
// shown to the client once; only its sha256 is stored (see api_tokens).
const TOKEN_PREFIX = "tt_";
const TOKEN_TTL_DAYS = 180;
const TOUCH_INTERVAL_MS = 5 * 60 * 1000;

export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

function generateToken(): string {
  return TOKEN_PREFIX + randomBytes(32).toString("base64url");
}

function tokenExpiry(): Date {
  return new Date(Date.now() + TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000);
}

async function issueToken(userId: string, deviceName?: string | null): Promise<string> {
  const token = generateToken();
  await storage.createApiToken({
    userId,
    tokenHash: hashToken(token),
    deviceName: deviceName ?? null,
    expiresAt: tokenExpiry(),
  });
  return token;
}

// Authenticates `Authorization: Bearer …` requests by setting req.user, which
// is all passport's req.isAuthenticated() checks. Runs after the session
// middleware so cookie sessions keep working unchanged.
export async function bearerAuth(req: Request, _res: Response, next: NextFunction) {
  if (req.user) return next();
  const header = req.headers.authorization;
  if (!header || !header.startsWith("Bearer ")) return next();

  const token = header.slice("Bearer ".length).trim();
  if (!token.startsWith(TOKEN_PREFIX)) return next();

  try {
    const hash = hashToken(token);
    const record = await storage.getApiTokenByHash(hash);
    if (!record || record.revokedAt || (record.expiresAt && record.expiresAt < new Date())) {
      return next();
    }
    const user = await storage.getUser(record.userId);
    if (!user) return next();

    req.user = user;
    (req as any).apiTokenId = record.id;
    if (!record.lastUsedAt || Date.now() - record.lastUsedAt.getTime() > TOUCH_INTERVAL_MS) {
      // Sliding expiry; failures here must not fail the request
      storage.touchApiToken(record.id, tokenExpiry()).catch(() => {});
    }
    next();
  } catch (error) {
    next(error);
  }
}

const credentialsSchema = z.object({
  email: z.string().trim().toLowerCase().email().max(254),
  password: z.string().min(6).max(200),
  deviceName: z.string().trim().max(120).optional(),
});

const registerSchema = credentialsSchema.extend({
  firstName: z.string().trim().max(60).optional(),
  lastName: z.string().trim().max(60).optional(),
});

export function registerTokenRoutes(app: Express) {
  app.post("/api/auth/register", async (req: Request, res: Response) => {
    const parsed = registerSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ message: "Invalid registration data", errors: parsed.error.errors });
    }
    const { email, password, firstName, lastName, deviceName } = parsed.data;

    try {
      if (await storage.getUserByEmail(email)) {
        return res.status(400).json({ message: "Email already exists" });
      }
      const user = await storage.createUser({
        email,
        password: await hashPassword(password),
        firstName,
        lastName,
      });
      const token = await issueToken(user.id, deviceName);
      res.status(201).json({ token, user: publicUser(user) });
    } catch (error) {
      console.error("Token registration error:", error);
      res.status(500).json({ message: "Registration failed" });
    }
  });

  app.post("/api/auth/token", async (req: Request, res: Response) => {
    const parsed = credentialsSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ message: "Email and password are required" });
    }
    const { email, password, deviceName } = parsed.data;

    try {
      const user = await storage.getUserByEmail(email);
      if (!user || !(await comparePasswords(password, user.password))) {
        return res.status(401).json({ message: "Incorrect email or password" });
      }
      const token = await issueToken(user.id, deviceName);
      res.json({ token, user: publicUser(user) });
    } catch (error) {
      console.error("Token login error:", error);
      res.status(500).json({ message: "Login failed" });
    }
  });

  app.get("/api/auth/tokens", requireUser, async (req: Request, res: Response) => {
    try {
      const tokens = await storage.listApiTokens(req.user!.id);
      res.json(tokens.map((t) => ({
        id: t.id,
        deviceName: t.deviceName,
        createdAt: t.createdAt,
        lastUsedAt: t.lastUsedAt,
        current: t.id === (req as any).apiTokenId,
      })));
    } catch (error) {
      console.error("Error listing tokens:", error);
      res.status(500).json({ message: "Failed to list tokens" });
    }
  });

  // Revokes the token used for this request (sign out on this device)
  app.delete("/api/auth/token", requireUser, async (req: Request, res: Response) => {
    const tokenId = (req as any).apiTokenId as number | undefined;
    if (!tokenId) {
      return res.status(400).json({ message: "Request was not authenticated with a token" });
    }
    try {
      await storage.revokeApiToken(tokenId, req.user!.id);
      res.status(204).end();
    } catch (error) {
      console.error("Error revoking token:", error);
      res.status(500).json({ message: "Failed to revoke token" });
    }
  });

  app.delete("/api/auth/tokens/:id", requireUser, async (req: Request, res: Response) => {
    const id = parseInt(req.params.id);
    if (isNaN(id)) return res.status(400).json({ message: "Invalid token ID" });
    try {
      const revoked = await storage.revokeApiToken(id, req.user!.id);
      if (!revoked) return res.status(404).json({ message: "Token not found" });
      res.status(204).end();
    } catch (error) {
      console.error("Error revoking token:", error);
      res.status(500).json({ message: "Failed to revoke token" });
    }
  });
}

function requireUser(req: Request, res: Response, next: NextFunction) {
  if (req.isAuthenticated()) return next();
  res.status(401).json({ message: "Unauthorized" });
}
