// Vercel entrypoint: the Express app runs as a single Vercel Function and
// handles /api/*. The client is built to public/ and served from the CDN
// (see vercel.json). Locally, use `npm run dev` / `npm start` instead.
import "express";
import app from "./server/app.js";

export default app;
