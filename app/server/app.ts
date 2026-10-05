import express, { type Request, Response, NextFunction } from "express";
import helmet from "helmet";
import { registerRoutes } from "./routes/index";
import { log } from "./log";

// The Express app: middleware and API routes. server/index.ts adds the
// client (Vite in dev, static files in production) and starts listening.
const app = express();
app.disable("x-powered-by");

// Security headers (API-4). The strict CSP only applies in production: Vite's
// dev server injects inline scripts and a websocket for hot reload.
const isProduction = app.get("env") === "production";
app.use(
  helmet({
    contentSecurityPolicy: isProduction
      ? {
          directives: {
            defaultSrc: ["'self'"],
            scriptSrc: ["'self'"],
            styleSrc: ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com"],
            fontSrc: ["'self'", "https://fonts.gstatic.com", "data:"],
            imgSrc: ["'self'", "data:", "blob:"],
            connectSrc: ["'self'"],
            frameAncestors: ["'none'"],
            objectSrc: ["'none'"],
            baseUri: ["'self'"],
            formAction: ["'self'"],
          },
        }
      : false,
    xFrameOptions: { action: "deny" },
    strictTransportSecurity: isProduction ? { maxAge: 15552000, includeSubDomains: true } : false,
    // The landing page posts to /api/waitlist cross-origin
    crossOriginResourcePolicy: { policy: "same-site" },
  }),
);

app.use(express.json({ limit: "100kb" }));
app.use(express.urlencoded({ extended: false, limit: "100kb" }));

// Method, path, status and timing only. Response bodies carry emails and
// session data, so they never go to the logs (API-8).
app.use((req, res, next) => {
  const start = Date.now();
  const path = req.path;
  res.on("finish", () => {
    if (path.startsWith("/api")) {
      log(`${req.method} ${path} ${res.statusCode} in ${Date.now() - start}ms`);
    }
  });
  next();
});

registerRoutes(app);

// Unknown API routes should 404 as JSON rather than fall through to the SPA.
app.use("/api", (_req: Request, res: Response) => {
  res.status(404).json({ message: "Not found" });
});

app.use((err: any, _req: Request, res: Response, _next: NextFunction) => {
  const status = err.status || err.statusCode || 500;
  // 4xx messages are meant for the client; 5xx messages can carry database
  // or library internals, so those stay in the server log (API-3).
  const message = status >= 500 ? "Internal Server Error" : err.message || "Bad request";

  if (status >= 500) console.error(err);
  res.status(status).json({ message });
});

export default app;
