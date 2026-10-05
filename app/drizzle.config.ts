import { defineConfig } from "drizzle-kit";

// Schema changes run as the database owner. In production DATABASE_URL is the
// restricted app_rw_login role (no DDL), so MIGRATION_DATABASE_URL carries the
// owner credentials; it falls back to DATABASE_URL when unset (local dev).
const url = process.env.MIGRATION_DATABASE_URL || process.env.DATABASE_URL;
if (!url) {
  throw new Error("MIGRATION_DATABASE_URL or DATABASE_URL must be set");
}

export default defineConfig({
  out: "./migrations",
  schema: "./shared/schema.ts",
  dialect: "postgresql",
  dbCredentials: {
    url,
  },
});
