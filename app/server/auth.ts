import passport from "passport";
import { Strategy as LocalStrategy } from "passport-local";
import { Express } from "express";
import session from "express-session";
import { scrypt, randomBytes, timingSafeEqual } from "crypto";
import { promisify } from "util";
import { storage } from "./storage";
import { User as SelectUser } from "@shared/schema";
import connectPg from "connect-pg-simple";
import { z } from "zod";
import { createAuthLimiter } from "./rateLimit";

declare global {
  namespace Express {
    interface User extends SelectUser {}
  }
}

const scryptAsync = promisify(scrypt);

export async function hashPassword(password: string) {
  const salt = randomBytes(16).toString("hex");
  const buf = (await scryptAsync(password, salt, 64)) as Buffer;
  return `${buf.toString("hex")}.${salt}`;
}

export async function comparePasswords(supplied: string, stored: string) {
  const [hashed, salt] = stored.split(".");
  const hashedBuf = Buffer.from(hashed, "hex");
  const suppliedBuf = (await scryptAsync(supplied, salt, 64)) as Buffer;
  return timingSafeEqual(hashedBuf, suppliedBuf);
}

// The user fields that are safe to send to clients
export function publicUser(user: SelectUser) {
  return {
    id: user.id,
    email: user.email,
    firstName: user.firstName,
    lastName: user.lastName,
    displayName: user.displayName,
    avatarEmoji: user.avatarEmoji,
    createdAt: user.createdAt,
  };
}

export const MIN_PASSWORD_LENGTH = 8;

// Emails are compared case-insensitively, so store and look them up lowercased
const emailSchema = z.string().trim().toLowerCase().email().max(254);

const registerSchema = z.object({
  email: emailSchema,
  password: z.string().min(MIN_PASSWORD_LENGTH, `Password must be at least ${MIN_PASSWORD_LENGTH} characters`).max(1024),
  firstName: z.string().trim().max(60).optional(),
  lastName: z.string().trim().max(60).optional(),
});

export function setupAuth(app: Express) {
  const sessionSecret = process.env.SESSION_SECRET;
  if (!sessionSecret || (app.get("env") === "production" && sessionSecret.length < 32)) {
    throw new Error("SESSION_SECRET must be set (at least 32 characters in production)");
  }

  const sessionTtl = 7 * 24 * 60 * 60 * 1000; // 1 week
  const pgStore = connectPg(session);
  const sessionStore = new pgStore({
    conString: process.env.DATABASE_URL,
    createTableIfMissing: true,
    ttl: sessionTtl,
    tableName: "sessions",
  });

  const sessionSettings: session.SessionOptions = {
    secret: sessionSecret,
    resave: false,
    saveUninitialized: false,
    store: sessionStore,
    cookie: {
      httpOnly: true,
      secure: "auto", // HTTPS-only cookie whenever the request came in over HTTPS
      sameSite: "lax", // explicit: Safari and Firefox don't default to Lax
      maxAge: sessionTtl,
    },
  };

  app.set("trust proxy", 1);
  app.use(session(sessionSettings));
  app.use(passport.initialize());
  app.use(passport.session());

  const authLimiter = createAuthLimiter();

  passport.use(
    new LocalStrategy({ usernameField: 'email' }, async (email, password, done) => {
      try {
        const parsed = emailSchema.safeParse(email);
        const user = parsed.success ? await storage.getUserByEmail(parsed.data) : undefined;
        if (!user || !(await comparePasswords(password, user.password!))) {
          return done(null, false);
        }
        return done(null, user);
      } catch (error) {
        return done(error);
      }
    }),
  );

  passport.serializeUser((user, done) => done(null, user.id));
  passport.deserializeUser(async (id: string, done) => {
    try {
      const user = await storage.getUser(id);
      done(null, user);
    } catch (error) {
      done(error);
    }
  });

  app.post("/api/register", authLimiter, async (req, res, next) => {
    try {
      const parsed = registerSchema.safeParse(req.body);
      if (!parsed.success) {
        return res.status(400).json({ message: parsed.error.issues[0]?.message ?? "Invalid email or password" });
      }
      const { email, password, firstName, lastName } = parsed.data;

      const existingUser = await storage.getUserByEmail(email);
      if (existingUser) {
        return res.status(400).json({ message: "Email already exists" });
      }

      const hashedPassword = await hashPassword(password);
      const user = await storage.createUser({
        email,
        password: hashedPassword,
        firstName,
        lastName,
      });

      req.login(user, (err) => {
        if (err) return next(err);
        res.status(201).json(publicUser(user));
      });
    } catch (error) {
      console.error("Registration error:", error);
      res.status(500).json({ message: "Registration failed" });
    }
  });

  app.post("/api/login", authLimiter, passport.authenticate("local"), (req, res) => {
    res.status(200).json(publicUser(req.user as SelectUser));
  });

  app.post("/api/logout", (req, res, next) => {
    req.logout((err) => {
      if (err) return next(err);
      res.sendStatus(200);
    });
  });

  app.get("/api/user", (req, res) => {
    if (!req.isAuthenticated()) return res.sendStatus(401);
    res.json(publicUser(req.user as SelectUser));
  });
}

export function isAuthenticated(req: any, res: any, next: any) {
  if (req.isAuthenticated()) {
    return next();
  }
  res.status(401).json({ message: "Unauthorized" });
}