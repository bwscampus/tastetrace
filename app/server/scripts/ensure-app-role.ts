/**
 * Create/refresh the least-privilege database role the web app runs as.
 *
 *   npm run db:roles      # predeploy, after `npm run db:push`
 *
 * Same contract as the API's `python -m app.db_roles`:
 * - app_rw: NOLOGIN group with DML on every table in `public`, sequence usage, and
 *   default privileges for tables created later. No DDL, not a superuser, no BYPASSRLS.
 * - app_rw_login: LOGIN member of app_rw. Created, and its password (re)set, only when
 *   APP_DB_PASSWORD is set; changing the variable rotates it on the next deploy.
 *
 * Connects with the owner credentials (MIGRATION_DATABASE_URL, else DATABASE_URL).
 * Idempotent. The password is quoted server-side by format('%L') and never logged.
 * Production Standard: DB-6.
 */
import pg from "pg";
import { pathToFileURL } from "url";

export const GROUP_ROLE = "app_rw";
export const LOGIN_ROLE = "app_rw_login";

const GROUP_SQL = [
  `DO $$ BEGIN
     IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${GROUP_ROLE}') THEN
       CREATE ROLE ${GROUP_ROLE} NOLOGIN;
     END IF;
   END $$`,
  `ALTER ROLE ${GROUP_ROLE} NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS`,
  `DO $$ BEGIN
     EXECUTE format('GRANT CONNECT ON DATABASE %I TO ${GROUP_ROLE}', current_database());
   END $$`,
  // Postgres < 15 lets every role create tables in public; only the owner should.
  `REVOKE CREATE ON SCHEMA public FROM PUBLIC`,
  `GRANT USAGE ON SCHEMA public TO ${GROUP_ROLE}`,
  `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ${GROUP_ROLE}`,
  `GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ${GROUP_ROLE}`,
  `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${GROUP_ROLE}`,
  `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO ${GROUP_ROLE}`,
];

const LOGIN_SQL = [
  `DO $$ BEGIN
     IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${LOGIN_ROLE}') THEN
       CREATE ROLE ${LOGIN_ROLE} LOGIN;
     END IF;
   END $$`,
  `GRANT ${GROUP_ROLE} TO ${LOGIN_ROLE}`,
];

export async function ensureAppRoles(client: pg.ClientBase, password: string | undefined): Promise<void> {
  await client.query("BEGIN");
  try {
    for (const sql of GROUP_SQL) await client.query(sql);
    if (password) {
      for (const sql of LOGIN_SQL) await client.query(sql);
      // ALTER ROLE can't take a bind parameter, so let Postgres quote the literal.
      const { rows } = await client.query<{ stmt: string }>(
        `SELECT format('ALTER ROLE ${LOGIN_ROLE} WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS INHERIT PASSWORD %L', $1::text) AS stmt`,
        [password],
      );
      await client.query(rows[0].stmt);
    }
    await client.query("COMMIT");
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  }
}

async function main(): Promise<void> {
  const url = process.env.MIGRATION_DATABASE_URL || process.env.DATABASE_URL;
  if (!url) throw new Error("MIGRATION_DATABASE_URL or DATABASE_URL must be set");
  const client = new pg.Client({ connectionString: url });
  await client.connect();
  try {
    await ensureAppRoles(client, process.env.APP_DB_PASSWORD || undefined);
  } finally {
    await client.end();
  }
  console.log(
    process.env.APP_DB_PASSWORD
      ? `Database roles up to date (${GROUP_ROLE}, ${LOGIN_ROLE})`
      : `Database roles up to date (${GROUP_ROLE}; APP_DB_PASSWORD unset, skipped ${LOGIN_ROLE})`,
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((err) => {
    // pg errors don't include the connection string or the password.
    console.error("db:roles failed:", err instanceof Error ? err.message : err);
    process.exit(1);
  });
}
