import { createServer } from "http";
import app from "./app";
import { setupVite, serveStatic } from "./vite";
import { log } from "./log";

(async () => {
  const server = createServer(app);

  // importantly only setup vite in development and after
  // setting up all the other routes so the catch-all route
  // doesn't interfere with the other routes
  if (app.get("env") === "development") {
    await setupVite(app, server);
  } else {
    serveStatic(app);
  }

  // Serves both the API and the client. Defaults to 5000 (the only port
  // Replit exposes); override with PORT elsewhere.
  const port = Number(process.env.PORT) || 5000;
  server.listen({ port, host: "0.0.0.0" }, () => {
    log(`serving on port ${port}`);
  });
})();
