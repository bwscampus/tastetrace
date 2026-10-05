import { describe, it, expect, beforeAll } from "vitest";
import request from "supertest";

// Integration tests against a real Postgres (DATABASE_URL); skipped otherwise.
const hasDb = !!process.env.DATABASE_URL;
process.env.SESSION_SECRET ??= "test-secret";

describe.skipIf(!hasDb)("web API", () => {
  let app: import("express").Express;
  const suffix = Date.now();
  const alice = { email: `Alice-${suffix}@Example.com`, password: "pw-12345678" };
  const bob = { email: `bob-${suffix}@example.com`, password: "pw-12345678" };
  // Cookie-session agents: each keeps its own session cookie between requests
  let aliceAgent: ReturnType<typeof request.agent>;
  let bobAgent: ReturnType<typeof request.agent>;

  beforeAll(async () => {
    app = (await import("../server/app")).default;
    aliceAgent = request.agent(app);
    bobAgent = request.agent(app);
    const a = await aliceAgent.post("/api/register").send({ ...alice, firstName: "Alice" });
    expect(a.status).toBe(201);
    const b = await bobAgent.post("/api/register").send(bob);
    expect(b.status).toBe(201);
  });

  it("answers the health check from the database, revealing nothing else", async () => {
    const res = await request(app).get("/api/health");
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: "ok" });
  });

  it("is honest that web password reset isn't available, for any address", async () => {
    const known = await request(app).post("/api/forgot-password").send({ email: alice.email });
    const unknown = await request(app).post("/api/forgot-password").send({ email: "nobody@example.com" });
    expect(known.status).toBe(200);
    expect(unknown.status).toBe(200);
    expect(known.body).toEqual(unknown.body);
    expect(known.body.message).not.toMatch(/sent/i);
  });

  it("signs users in with a session cookie and normalizes email case", async () => {
    const me = await aliceAgent.get("/api/user");
    expect(me.status).toBe(200);
    expect(me.body.email).toBe(alice.email.toLowerCase());
    expect(me.body).toHaveProperty("displayName");

    const login = await request(app).post("/api/login").send({ email: alice.email.toUpperCase(), password: alice.password });
    expect(login.status).toBe(200);
    expect(login.headers["set-cookie"]?.[0]).toMatch(/SameSite=Lax/i);

    const dupe = await request(app).post("/api/register").send({ email: alice.email.toLowerCase(), password: alice.password });
    expect(dupe.status).toBe(400);

    const bad = await request(app).post("/api/login").send({ ...alice, password: "wrong-pw" });
    expect(bad.status).toBe(401);
  });

  it("rejects short passwords at registration", async () => {
    const res = await request(app).post("/api/register").send({ email: `short-${suffix}@example.com`, password: "pw123" });
    expect(res.status).toBe(400);
  });

  it("stores symptoms with intensity, severity, backdated timestamp and local date", async () => {
    const created = await aliceAgent.post("/api/symptoms").send({
      name: "Acid Reflux", catalogKey: "acid_reflux", intensity: 3,
      timestamp: "2026-09-11T21:29:00Z", tz: "America/Los_Angeles", durationMinutes: 60,
    });
    expect(created.status).toBe(201);
    expect(created.body.severity).toBe("Moderate");
    expect(created.body.intensity).toBe(3);
    expect(created.body.date).toBe("2026-09-11");
    expect(created.body.timestamp).toBe("2026-09-11T21:29:00.000Z");
    expect(created.body.emoji).toBe("🔥");

    // Web-style write gets a derived intensity
    const web = await aliceAgent.post("/api/symptoms").send({ name: "Headache", severity: "Severe" });
    expect(web.status).toBe(201);
    expect(web.body.intensity).toBe(4);

    const updated = await aliceAgent.put(`/api/symptoms/${created.body.id}`)
      .send({ timestamp: "2026-09-12T22:00:00Z", tz: "America/Los_Angeles" });
    expect(updated.status).toBe(200);
    expect(updated.body.date).toBe("2026-09-12");

    const invalid = await aliceAgent.post("/api/symptoms").send({ name: "x", intensity: 9 });
    expect(invalid.status).toBe(400);
  });

  it("logs several symptoms in one batch", async () => {
    const batch = await aliceAgent.post("/api/symptoms/batch").send({
      timestamp: "2026-09-11T21:29:00Z", tz: "America/Los_Angeles",
      items: [{ name: "Acid Reflux", catalogKey: "acid_reflux", intensity: 3 }, { name: "Bloating", catalogKey: "bloating", intensity: 1 }],
    });
    expect(batch.status).toBe(201);
    expect(batch.body).toHaveLength(2);
    expect(batch.body[1].severity).toBe("Mild");
  });

  it("enforces ownership on meals and symptoms", async () => {
    const meal = await aliceAgent.post("/api/meals")
      .send({ name: "Avocado Sourdough Toast", mealType: "Lunch", ingredientDetails: [{ name: "sourdough bread", cookMethod: "toasted" }, { name: "avocado" }] });
    expect(meal.status).toBe(201);
    expect(meal.body.ingredients).toEqual(["sourdough bread", "avocado"]);

    expect((await bobAgent.get(`/api/meals/${meal.body.id}`)).status).toBe(404);
    expect((await bobAgent.put(`/api/meals/${meal.body.id}`).send({ name: "x" })).status).toBe(404);
    expect((await bobAgent.delete(`/api/meals/${meal.body.id}`)).status).toBe(404);
    expect((await aliceAgent.get(`/api/meals/${meal.body.id}`)).status).toBe(200);

    // Editing notes no longer rewrites the ingredient list
    const edited = await aliceAgent.put(`/api/meals/${meal.body.id}`).send({ notes: "with, extra, commas" });
    expect(edited.body.ingredients).toEqual(["sourdough bread", "avocado"]);

    const symptoms = await aliceAgent.get("/api/symptoms");
    const mine = symptoms.body[0];
    expect((await bobAgent.delete(`/api/symptoms/${mine.id}`)).status).toBe(404);
  });

  it("serves profile and settings", async () => {
    const settings = await aliceAgent.get("/api/settings");
    expect(settings.status).toBe(200);
    expect(settings.body.correlationWindowHours).toBe(24);

    const patched = await aliceAgent.patch("/api/settings").send({ timezone: "America/Los_Angeles", streakMealsPerDay: 3 });
    expect(patched.body.timezone).toBe("America/Los_Angeles");
    expect((await aliceAgent.patch("/api/settings").send({ timezone: "Mars/Olympus" })).status).toBe(400);

    const profile = await aliceAgent.patch("/api/profile").send({ displayName: "Taylor", sensitivityTags: ["gluten"] });
    expect(profile.status).toBe(200);
    expect(profile.body.displayName).toBe("Taylor");
    expect(profile.body.sensitivityTags).toEqual(["gluten"]);
    expect(profile.body.journalerDays).toBeGreaterThanOrEqual(1);

    const catalog = await aliceAgent.get("/api/symptom-catalog");
    expect(catalog.body.defaults).toHaveLength(6);
  });

  it("saves dishes and logs meals from them", async () => {
    const dish = await aliceAgent.post("/api/dishes").send({
      name: "Avocado Sourdough Toast", emoji: "🥑", containsGluten: true,
      ingredients: [{ name: "sourdough bread", cookMethod: "toasted" }, { name: "avocado", cookMethod: "raw" }, { name: "salt" }],
    });
    expect(dish.status).toBe(201);
    expect(dish.body.timesLogged).toBe(0);

    const logged = await aliceAgent.post(`/api/dishes/${dish.body.id}/log`)
      .send({ mealType: "Lunch", timestamp: "2026-09-11T19:45:00Z", tz: "America/Los_Angeles" });
    expect(logged.status).toBe(201);
    expect(logged.body.dishId).toBe(dish.body.id);
    expect(logged.body.ingredients).toEqual(["sourdough bread", "avocado", "salt"]);
    expect(logged.body.ingredientDetails[0].cookMethod).toBe("toasted");
    expect(logged.body.containsGluten).toBe(true);
    expect(logged.body.date).toBe("2026-09-11");

    const list = await aliceAgent.get("/api/dishes");
    expect(list.body[0].timesLogged).toBe(1);
    expect(list.body[0].lastLoggedAt).toBe("2026-09-11T19:45:00.000Z");

    expect((await bobAgent.post(`/api/dishes/${dish.body.id}/log`).send({ mealType: "Lunch" })).status).toBe(404);
    expect((await aliceAgent.post(`/api/dishes/${dish.body.id}/log`).send({ mealType: "Brunch" })).status).toBe(400);

    const renamed = await aliceAgent.put(`/api/dishes/${dish.body.id}`).send({ emoji: "🍞" });
    expect(renamed.body.emoji).toBe("🍞");
    expect((await aliceAgent.delete(`/api/dishes/${dish.body.id}`)).status).toBe(204);
    // The logged meal survives with its dish link cleared
    const meal = await aliceAgent.get(`/api/meals/${logged.body.id}`);
    expect(meal.body.dishId).toBeNull();
  });

  it("reports daily coverage", async () => {
    await aliceAgent.post("/api/meals").send({ name: "Oats", mealType: "Breakfast", timestamp: "2026-09-17T15:15:00Z", tz: "America/Los_Angeles" });
    const coverage = await aliceAgent.get("/api/coverage?date=2026-09-17&tz=America/Los_Angeles");
    expect(coverage.status).toBe(200);
    expect(coverage.body.slots.Breakfast).toMatchObject({ logged: true, time: "08:15" });
    expect(coverage.body.slotTotal).toBe(3);
    expect(coverage.body.week).toHaveLength(7);
    expect(coverage.body.streak.threshold).toBe(3); // patched in the settings test
    expect((await aliceAgent.get("/api/coverage?date=nope")).status).toBe(400);
  });

  it("serves digests, suspects, trigger insights and the watchlist", async () => {
    // Alice already has: meals on Sep 11 (from dish) + Sep 17 breakfast, symptoms on Sep 11/12 and a batch on Sep 11
    await aliceAgent.post("/api/watchlist").send({ ingredient: "Sourdough Bread", source: "suspect" });
    const watch = await aliceAgent.get("/api/watchlist");
    expect(watch.status).toBe(200);
    expect(watch.body[0]).toMatchObject({ ingredient: "sourdough bread", source: "suspect" });
    expect(watch.body[0]).toHaveProperty("confidenceMax");

    const digest = await aliceAgent.get("/api/digest/weekly?weekStart=2026-09-11&tz=America/Los_Angeles");
    expect(digest.status).toBe(200);
    expect(digest.body.weekEnd).toBe("2026-09-17");
    expect(digest.body.trends.days).toHaveLength(7);
    expect(digest.body.trends.days[0].date).toBe("2026-09-11");
    expect(digest.body.symptoms.cards.length).toBeGreaterThan(0);
    expect((await aliceAgent.get("/api/digest/weekly?weekStart=bad")).status).toBe(400);
    expect((await aliceAgent.get("/api/digest/weekly")).status).toBe(200);

    const suspects = await aliceAgent.get("/api/digest/suspects?weekStart=2026-09-11&tz=America/Los_Angeles");
    expect(suspects.status).toBe(200);
    expect(suspects.body.windowHours).toBe(24);
    expect(suspects.body.symptomFilters[0].name).toBe("All Symptoms");
    expect(Array.isArray(suspects.body.ingredients)).toBe(true);

    const insights = await aliceAgent.get("/api/insights/triggers?dimension=ingredient&minConfidence=0");
    expect(insights.status).toBe(200);
    expect(insights.body).toMatchObject({ dimension: "ingredient", minConfidence: 0 });
    expect(insights.body.symptoms.length).toBeGreaterThan(0);
    expect((await aliceAgent.get("/api/insights/triggers?minConfidence=200")).status).toBe(400);

    // Web-shaped correlations still work and never expose cook methods
    const web = await aliceAgent.get("/api/correlations");
    expect(web.status).toBe(200);
    expect(web.body.every((c: any) => c.dimension !== "cook_method")).toBe(true);

    expect((await aliceAgent.delete(`/api/watchlist/${watch.body[0].id}`)).status).toBe(204);
  });

  it("flags meals followed by symptoms as suspicious", async () => {
    const meal = await aliceAgent.post("/api/meals")
      .send({ name: "Late pizza", mealType: "Dinner", timestamp: "2026-09-20T02:00:00Z", tz: "America/Los_Angeles", ingredientDetails: [{ name: "cheese" }] });
    await aliceAgent.post("/api/symptoms").send({ name: "Bloating", intensity: 2, timestamp: "2026-09-20T04:00:00Z", tz: "America/Los_Angeles" });
    const day = await aliceAgent.get("/api/entries/date?date=2026-09-19&tz=America/Los_Angeles");
    const flagged = day.body.meals.find((m: any) => m.id === meal.body.id);
    expect(flagged.suspiciousFor).toEqual(["Bloating"]);
    expect(["window", "correlated"]).toContain(flagged.suspicion);
    expect(day.body.flares).toBe(1); // 04:00Z on the 20th is 9 PM on the 19th in Los Angeles
    expect(day.body.symptoms).toHaveLength(1);
  });

  it("synthesises a pattern summary, cached until the data changes", async () => {
    const first = await aliceAgent.post("/api/ai/synthesis").send({ weekStart: "2026-09-11", tz: "America/Los_Angeles" });
    expect(first.status).toBe(200);
    expect(first.body.source).toBe(process.env.ANTHROPIC_API_KEY ? "claude" : "rules");
    expect(first.body.cached).toBe(false);
    expect(first.body.text.length).toBeGreaterThan(20);
    const second = await aliceAgent.post("/api/ai/synthesis").send({ weekStart: "2026-09-11", tz: "America/Los_Angeles" });
    expect(second.body.cached).toBe(true);
    expect(second.body.text).toBe(first.body.text);
    expect((await aliceAgent.post("/api/ai/synthesis").send({ weekStart: "nope" })).status).toBe(400);
  });

  it("exports CSV and a ledger bundle", async () => {
    const csv = await aliceAgent.get("/api/export/csv?from=2026-09-01&to=2026-09-30&tz=America/Los_Angeles");
    expect(csv.status).toBe(200);
    expect(csv.headers["content-type"]).toContain("text/csv");
    expect(csv.headers["content-disposition"]).toContain("tastetrace-2026-09-01-2026-09-30.csv");
    const lines = csv.text.trim().split("\n");
    expect(lines[0]).toBe("entry_type,id,date,time,name,meal_type,ingredients,cook_methods,dish,intensity,severity,duration_minutes,notes,timestamp_utc");
    expect(lines.some((l) => l.startsWith("meal,") && l.includes("Avocado Sourdough Toast") && l.includes("sourdough bread; avocado"))).toBe(true);
    expect(lines.some((l) => l.startsWith("symptom,") && l.includes("Acid Reflux"))).toBe(true);
    expect((await aliceAgent.get("/api/export/csv?from=2026-09-30&to=2026-09-01")).status).toBe(400);

    const ledger = await aliceAgent.get("/api/export/ledger?from=2026-09-01&to=2026-09-30&tz=America/Los_Angeles");
    expect(ledger.status).toBe(200);
    expect(ledger.body.range).toEqual({ from: "2026-09-01", to: "2026-09-30", tz: "America/Los_Angeles" });
    expect(ledger.body.profile.email).toBe(alice.email.toLowerCase());
    expect(ledger.body.days.length).toBeGreaterThan(0);
    expect(ledger.body.days[0].meals[0] ?? ledger.body.days[0].symptoms[0]).toBeDefined();
    expect(ledger.body.digestWeeks.length).toBeGreaterThan(0);
    expect(Array.isArray(ledger.body.triggers)).toBe(true);
  });

  it("rate-limits repeated logins", async () => {
    const statuses: number[] = [];
    for (let i = 0; i < 12; i++) {
      statuses.push((await request(app).post("/api/login").send({ ...alice, password: "wrong-pw" })).status);
    }
    expect(statuses).toContain(429);
  });

  it("logs out", async () => {
    expect((await bobAgent.post("/api/logout")).status).toBe(200);
    expect((await bobAgent.get("/api/user")).status).toBe(401);
  });
});
