import { describe, it, expect, beforeAll, afterAll } from "vitest";
import pg from "pg";
import { ensureAppRoles, LOGIN_ROLE } from "../server/scripts/ensure-app-role";

// DB-6: the web app's role can read/write data but not change the schema.
// Needs a real Postgres with owner credentials (DATABASE_URL); skipped otherwise.
const ownerUrl = process.env.DATABASE_URL;
const PASSWORD = "app-role-test-pw";

function loginUrl(password: string): string {
  const url = new URL(ownerUrl!);
  url.username = LOGIN_ROLE;
  url.password = password;
  return url.toString();
}

async function asApp<T>(password: string, fn: (c: pg.Client) => Promise<T>): Promise<T> {
  const client = new pg.Client({ connectionString: loginUrl(password) });
  await client.connect();
  try {
    return await fn(client);
  } finally {
    await client.end();
  }
}

describe.skipIf(!ownerUrl)("least-privilege app role", () => {
  const table = `t_roles_${Date.now()}`;
  let owner: pg.Client;

  beforeAll(async () => {
    owner = new pg.Client({ connectionString: ownerUrl });
    await owner.connect();
    await owner.query(`CREATE TABLE ${table} (id serial PRIMARY KEY, note text)`);
    await ensureAppRoles(owner, PASSWORD);
  });

  afterAll(async () => {
    await owner.query(`DROP TABLE IF EXISTS ${table}, ${table}_later`);
    await owner.end();
  });

  it("can insert, read, update and delete", async () => {
    await asApp(PASSWORD, async (c) => {
      await c.query(`INSERT INTO ${table} (note) VALUES ('hello')`);
      await c.query(`UPDATE ${table} SET note = 'updated'`);
      const { rows } = await c.query(`SELECT note FROM ${table}`);
      expect(rows[0].note).toBe("updated");
      await c.query(`DELETE FROM ${table}`);
    });
  });

  it("cannot create, alter, drop or truncate tables", async () => {
    for (const ddl of [
      "CREATE TABLE should_fail (id int)",
      `ALTER TABLE ${table} ADD COLUMN x int`,
      `DROP TABLE ${table}`,
      `TRUNCATE ${table}`,
    ]) {
      await expect(asApp(PASSWORD, (c) => c.query(ddl))).rejects.toThrow(/permission denied|must be owner/);
    }
  });

  it("is not a superuser and cannot bypass RLS", async () => {
    const row = await asApp(PASSWORD, async (c) =>
      (await c.query(
        "SELECT rolsuper, rolbypassrls, rolcreatedb, rolcreaterole FROM pg_roles WHERE rolname = current_user",
      )).rows[0],
    );
    expect(row).toEqual({ rolsuper: false, rolbypassrls: false, rolcreatedb: false, rolcreaterole: false });
  });

  it("covers tables created later and the session store", async () => {
    await owner.query(`CREATE TABLE ${table}_later (id serial PRIMARY KEY)`);
    await asApp(PASSWORD, (c) => c.query(`INSERT INTO ${table}_later DEFAULT VALUES`));

    const { rows } = await owner.query("SELECT to_regclass('public.sessions') AS t");
    if (rows[0].t) {
      // connect-pg-simple's table: the app must keep read/write access to it.
      await asApp(PASSWORD, (c) => c.query("SELECT count(*) FROM sessions"));
    }
  });

  it("is idempotent and rotates the password", async () => {
    await ensureAppRoles(owner, "rotated-pw");
    await asApp("rotated-pw", (c) => c.query(`SELECT 1 FROM ${table}`));
    await expect(asApp(PASSWORD, (c) => c.query("SELECT 1"))).rejects.toThrow(/password authentication failed/);
    await ensureAppRoles(owner, PASSWORD);
  });
});
