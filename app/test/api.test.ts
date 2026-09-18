import { describe, it, expect, beforeAll } from "vitest";
import request from "supertest";

// Integration tests against a real Postgres (DATABASE_URL); skipped otherwise.
const hasDb = !!process.env.DATABASE_URL;
process.env.SESSION_SECRET ??= "test-secret";

describe.skipIf(!hasDb)("mobile API", () => {
  let app: import("express").Express;
  const suffix = Date.now();
  const alice = { email: `alice-${suffix}@example.com`, password: "pw12345", deviceName: "vitest" };
  const bob = { email: `bob-${suffix}@example.com`, password: "pw12345", deviceName: "vitest" };
  let aliceToken = "";
  let bobToken = "";

  beforeAll(async () => {
    app = (await import("../server/app")).default;
    const a = await request(app).post("/api/auth/register").send({ ...alice, firstName: "Alice" });
    expect(a.status).toBe(201);
    aliceToken = a.body.token;
    const b = await request(app).post("/api/auth/register").send(bob);
    bobToken = b.body.token;
  });

  const auth = (token: string) => ({ authorization: `Bearer ${token}` });

  it("issues bearer tokens and identifies the user", async () => {
    expect(aliceToken.startsWith("tt_")).toBe(true);
    const me = await request(app).get("/api/user").set(auth(aliceToken));
    expect(me.status).toBe(200);
    expect(me.body.email).toBe(alice.email);
    expect(me.body).toHaveProperty("displayName");

    const login = await request(app).post("/api/auth/token").send(alice);
    expect(login.status).toBe(200);
    expect(login.body.token).not.toBe(aliceToken);

    const bad = await request(app).post("/api/auth/token").send({ ...alice, password: "wrong-pw" });
    expect(bad.status).toBe(401);
  });

  it("stores symptoms with intensity, severity, backdated timestamp and local date", async () => {
    const created = await request(app).post("/api/symptoms").set(auth(aliceToken)).send({
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
    const web = await request(app).post("/api/symptoms").set(auth(aliceToken)).send({ name: "Headache", severity: "Severe" });
    expect(web.status).toBe(201);
    expect(web.body.intensity).toBe(4);

    const updated = await request(app).put(`/api/symptoms/${created.body.id}`).set(auth(aliceToken))
      .send({ timestamp: "2026-09-12T22:00:00Z", tz: "America/Los_Angeles" });
    expect(updated.status).toBe(200);
    expect(updated.body.date).toBe("2026-09-12");

    const invalid = await request(app).post("/api/symptoms").set(auth(aliceToken)).send({ name: "x", intensity: 9 });
    expect(invalid.status).toBe(400);
  });

  it("logs several symptoms in one batch", async () => {
    const batch = await request(app).post("/api/symptoms/batch").set(auth(aliceToken)).send({
      timestamp: "2026-09-11T21:29:00Z", tz: "America/Los_Angeles",
      items: [{ name: "Acid Reflux", catalogKey: "acid_reflux", intensity: 3 }, { name: "Bloating", catalogKey: "bloating", intensity: 1 }],
    });
    expect(batch.status).toBe(201);
    expect(batch.body).toHaveLength(2);
    expect(batch.body[1].severity).toBe("Mild");
  });

  it("enforces ownership on meals and symptoms", async () => {
    const meal = await request(app).post("/api/meals").set(auth(aliceToken))
      .send({ name: "Avocado Sourdough Toast", mealType: "Lunch", ingredientDetails: [{ name: "sourdough bread", cookMethod: "toasted" }, { name: "avocado" }] });
    expect(meal.status).toBe(201);
    expect(meal.body.ingredients).toEqual(["sourdough bread", "avocado"]);

    expect((await request(app).get(`/api/meals/${meal.body.id}`).set(auth(bobToken))).status).toBe(404);
    expect((await request(app).put(`/api/meals/${meal.body.id}`).set(auth(bobToken)).send({ name: "x" })).status).toBe(404);
    expect((await request(app).delete(`/api/meals/${meal.body.id}`).set(auth(bobToken))).status).toBe(404);
    expect((await request(app).get(`/api/meals/${meal.body.id}`).set(auth(aliceToken))).status).toBe(200);

    // Editing notes no longer rewrites the ingredient list
    const edited = await request(app).put(`/api/meals/${meal.body.id}`).set(auth(aliceToken)).send({ notes: "with, extra, commas" });
    expect(edited.body.ingredients).toEqual(["sourdough bread", "avocado"]);

    const symptoms = await request(app).get("/api/symptoms").set(auth(aliceToken));
    const mine = symptoms.body[0];
    expect((await request(app).delete(`/api/symptoms/${mine.id}`).set(auth(bobToken))).status).toBe(404);
  });

  it("serves profile and settings", async () => {
    const settings = await request(app).get("/api/settings").set(auth(aliceToken));
    expect(settings.status).toBe(200);
    expect(settings.body.correlationWindowHours).toBe(24);

    const patched = await request(app).patch("/api/settings").set(auth(aliceToken)).send({ timezone: "America/Los_Angeles", streakMealsPerDay: 3 });
    expect(patched.body.timezone).toBe("America/Los_Angeles");
    expect((await request(app).patch("/api/settings").set(auth(aliceToken)).send({ timezone: "Mars/Olympus" })).status).toBe(400);

    const profile = await request(app).patch("/api/profile").set(auth(aliceToken)).send({ displayName: "Taylor", sensitivityTags: ["gluten"] });
    expect(profile.status).toBe(200);
    expect(profile.body.displayName).toBe("Taylor");
    expect(profile.body.sensitivityTags).toEqual(["gluten"]);
    expect(profile.body.journalerDays).toBeGreaterThanOrEqual(1);

    const catalog = await request(app).get("/api/symptom-catalog").set(auth(aliceToken));
    expect(catalog.body.defaults).toHaveLength(6);
  });

  it("saves dishes and logs meals from them", async () => {
    const dish = await request(app).post("/api/dishes").set(auth(aliceToken)).send({
      name: "Avocado Sourdough Toast", emoji: "🥑", containsGluten: true,
      ingredients: [{ name: "sourdough bread", cookMethod: "toasted" }, { name: "avocado", cookMethod: "raw" }, { name: "salt" }],
    });
    expect(dish.status).toBe(201);
    expect(dish.body.timesLogged).toBe(0);

    const logged = await request(app).post(`/api/dishes/${dish.body.id}/log`).set(auth(aliceToken))
      .send({ mealType: "Lunch", timestamp: "2026-09-11T19:45:00Z", tz: "America/Los_Angeles" });
    expect(logged.status).toBe(201);
    expect(logged.body.dishId).toBe(dish.body.id);
    expect(logged.body.ingredients).toEqual(["sourdough bread", "avocado", "salt"]);
    expect(logged.body.ingredientDetails[0].cookMethod).toBe("toasted");
    expect(logged.body.containsGluten).toBe(true);
    expect(logged.body.date).toBe("2026-09-11");

    const list = await request(app).get("/api/dishes").set(auth(aliceToken));
    expect(list.body[0].timesLogged).toBe(1);
    expect(list.body[0].lastLoggedAt).toBe("2026-09-11T19:45:00.000Z");

    expect((await request(app).post(`/api/dishes/${dish.body.id}/log`).set(auth(bobToken)).send({ mealType: "Lunch" })).status).toBe(404);
    expect((await request(app).post(`/api/dishes/${dish.body.id}/log`).set(auth(aliceToken)).send({ mealType: "Brunch" })).status).toBe(400);

    const renamed = await request(app).put(`/api/dishes/${dish.body.id}`).set(auth(aliceToken)).send({ emoji: "🍞" });
    expect(renamed.body.emoji).toBe("🍞");
    expect((await request(app).delete(`/api/dishes/${dish.body.id}`).set(auth(aliceToken))).status).toBe(204);
    // The logged meal survives with its dish link cleared
    const meal = await request(app).get(`/api/meals/${logged.body.id}`).set(auth(aliceToken));
    expect(meal.body.dishId).toBeNull();
  });

  it("reports daily coverage", async () => {
    await request(app).post("/api/meals").set(auth(aliceToken)).send({ name: "Oats", mealType: "Breakfast", timestamp: "2026-09-17T15:15:00Z", tz: "America/Los_Angeles" });
    const coverage = await request(app).get("/api/coverage?date=2026-09-17&tz=America/Los_Angeles").set(auth(aliceToken));
    expect(coverage.status).toBe(200);
    expect(coverage.body.slots.Breakfast).toMatchObject({ logged: true, time: "08:15" });
    expect(coverage.body.slotTotal).toBe(3);
    expect(coverage.body.week).toHaveLength(7);
    expect(coverage.body.streak.threshold).toBe(3); // patched in the settings test
    expect((await request(app).get("/api/coverage?date=nope").set(auth(aliceToken))).status).toBe(400);
  });

  it("serves digests, suspects, trigger insights and the watchlist", async () => {
    // Alice already has: meals on Sep 11 (from dish) + Sep 17 breakfast, symptoms on Sep 11/12 and a batch on Sep 11
    await request(app).post("/api/watchlist").set(auth(aliceToken)).send({ ingredient: "Sourdough Bread", source: "suspect" });
    const watch = await request(app).get("/api/watchlist").set(auth(aliceToken));
    expect(watch.status).toBe(200);
    expect(watch.body[0]).toMatchObject({ ingredient: "sourdough bread", source: "suspect" });
    expect(watch.body[0]).toHaveProperty("confidenceMax");

    const digest = await request(app).get("/api/digest/weekly?weekStart=2026-09-11&tz=America/Los_Angeles").set(auth(aliceToken));
    expect(digest.status).toBe(200);
    expect(digest.body.weekEnd).toBe("2026-09-17");
    expect(digest.body.trends.days).toHaveLength(7);
    expect(digest.body.trends.days[0].date).toBe("2026-09-11");
    expect(digest.body.symptoms.cards.length).toBeGreaterThan(0);
    expect((await request(app).get("/api/digest/weekly?weekStart=bad").set(auth(aliceToken))).status).toBe(400);
    expect((await request(app).get("/api/digest/weekly").set(auth(aliceToken))).status).toBe(200);

    const suspects = await request(app).get("/api/digest/suspects?weekStart=2026-09-11&tz=America/Los_Angeles").set(auth(aliceToken));
    expect(suspects.status).toBe(200);
    expect(suspects.body.windowHours).toBe(24);
    expect(suspects.body.symptomFilters[0].name).toBe("All Symptoms");
    expect(Array.isArray(suspects.body.ingredients)).toBe(true);

    const insights = await request(app).get("/api/insights/triggers?dimension=ingredient&minConfidence=0").set(auth(aliceToken));
    expect(insights.status).toBe(200);
    expect(insights.body).toMatchObject({ dimension: "ingredient", minConfidence: 0 });
    expect(insights.body.symptoms.length).toBeGreaterThan(0);
    expect((await request(app).get("/api/insights/triggers?minConfidence=200").set(auth(aliceToken))).status).toBe(400);

    // Web-shaped correlations still work and never expose cook methods
    const web = await request(app).get("/api/correlations").set(auth(aliceToken));
    expect(web.status).toBe(200);
    expect(web.body.every((c: any) => c.dimension !== "cook_method")).toBe(true);

    expect((await request(app).delete(`/api/watchlist/${watch.body[0].id}`).set(auth(aliceToken))).status).toBe(204);
  });

  it("flags meals followed by symptoms as suspicious", async () => {
    const meal = await request(app).post("/api/meals").set(auth(aliceToken))
      .send({ name: "Late pizza", mealType: "Dinner", timestamp: "2026-09-20T02:00:00Z", tz: "America/Los_Angeles", ingredientDetails: [{ name: "cheese" }] });
    await request(app).post("/api/symptoms").set(auth(aliceToken)).send({ name: "Bloating", intensity: 2, timestamp: "2026-09-20T04:00:00Z", tz: "America/Los_Angeles" });
    const day = await request(app).get("/api/entries/date?date=2026-09-19&tz=America/Los_Angeles").set(auth(aliceToken));
    const flagged = day.body.meals.find((m: any) => m.id === meal.body.id);
    expect(flagged.suspiciousFor).toEqual(["Bloating"]);
    expect(["window", "correlated"]).toContain(flagged.suspicion);
    expect(day.body.flares).toBe(1); // 04:00Z on the 20th is 9 PM on the 19th in Los Angeles
    expect(day.body.symptoms).toHaveLength(1);
  });

  it("synthesises a pattern summary, cached until the data changes", async () => {
    const first = await request(app).post("/api/ai/synthesis").set(auth(aliceToken)).send({ weekStart: "2026-09-11", tz: "America/Los_Angeles" });
    expect(first.status).toBe(200);
    expect(first.body.source).toBe(process.env.ANTHROPIC_API_KEY ? "claude" : "rules");
    expect(first.body.cached).toBe(false);
    expect(first.body.text.length).toBeGreaterThan(20);
    const second = await request(app).post("/api/ai/synthesis").set(auth(aliceToken)).send({ weekStart: "2026-09-11", tz: "America/Los_Angeles" });
    expect(second.body.cached).toBe(true);
    expect(second.body.text).toBe(first.body.text);
    expect((await request(app).post("/api/ai/synthesis").set(auth(aliceToken)).send({ weekStart: "nope" })).status).toBe(400);
  });

  it("revokes tokens", async () => {
    const list = await request(app).get("/api/auth/tokens").set(auth(aliceToken));
    expect(list.body.length).toBeGreaterThanOrEqual(2);
    expect(list.body.some((t: any) => t.current)).toBe(true);

    expect((await request(app).delete("/api/auth/token").set(auth(aliceToken))).status).toBe(204);
    expect((await request(app).get("/api/user").set(auth(aliceToken))).status).toBe(401);
  });
});
