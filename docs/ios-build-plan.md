# TasteTrace iOS App — Build Plan

> **Status (2026-09-18):** M0–M6 are implemented on the `ios-m0-backend` branch. The backend has 36 vitest tests (unit + integration against a scratch Postgres) and the Swift packages build with the command-line toolchain; `apismoke` runs 30 end-to-end checks against a live backend. Not yet done: running the app in the simulator and the XCTest suites (needs Xcode), the optional TestFlight step, and `DELETE /api/account` (required before App Store submission).

## Context

TasteTrace has a working web app (`app/`: React + Vite client, Express API, Postgres via Drizzle, deployed on Railway) and a static landing page (`landing/`). `PRODUCT.md` and the 16 mockups in `assets/` describe a native iOS app that goes well beyond the web app: daily coverage and streaks, saved dish tiles, ingredient + cook-method capture, a 1–5 intensity symptom grid, weekly digests (trends / symptoms / suspects), AI pattern synthesis, a watchlist, trigger insights with confidence tiers, PDF/CSV exports, a profile, and logging reminders. Barcode scanning, substitutes and restaurant recommendations from PRODUCT.md are out of scope for this plan.

Decisions made:
- **Native SwiftUI**, iOS 17+, in `ios/` in this repo.
- **Full mockup build**, planned up front, in six milestones.
- **Backend stays Express + Drizzle + Postgres** in `app/`; every change is additive and backward compatible so the untouched web app keeps working. Railway applies schema changes with `npm run db:push` before each deploy.
- **Xcode will be installed on this Mac** (setup steps below). Apple Developer account status is unknown, so everything is simulator-first; TestFlight is an optional last step.
- **AI synthesis runs server-side on the Claude API** (`claude-opus-5`, `ANTHROPIC_API_KEY` on Railway) with a rule-based fallback when the key is missing. The mockup's "OpenAI" badge becomes "AI".
- **Web app is left as-is.**

## Mockups → screens (source of truth)

| Mockup | Screen | Key elements |
|---|---|---|
| IMG_2419 | **Today** (tab 1) | Date header, bell + settings, "Signed in as", 7-day digest hero (discomfort index /10, % change, occurrences, sparkline, View Report), Daily Coverage card (2/3 ring, streak pill, Breakfast/Lunch/Dinner ticks, nudge time), Log Meal / Log Symptom buttons, Today's Timeline (events, filter, pending-slot placeholder), status toast |
| IMG_2420 | **Daily Logging Coverage** | Streak hero (day streak, rule "2+ meals/day", 7-day dots), Meal Coverage Wheel (0/3, slot tiles Pending/Logged), Post-dinner nudge card, 7-Day Log Breakdown (x/21 slots) |
| IMG_2421/2422 | **Log a Meal** (step 1) | Quick speed logs info, date & time, meal category grid (Breakfast/Lunch/Dinner/Snack), sensitivity filter chips (Gluten/Sugar/Dairy/Grain), saved dish tiles (name, Saved badge, ingredients, Edit, Delete, Grid Library), Write New Recipe + "Configure ingredients & prep styles" |
| IMG_2423 | **Verify Ingredients** (step 2) | Editable dish name, Sensitivity Trigger Traces card (watchlist alert / no flags), comma-separated ingredient input + Add, ingredient rows with cook method, first-log save suggestion, "Complete Meal & Review Save" |
| IMG_2424 | **Save custom dish?** sheet | Emoji stamp picker, dish name, ingredients summary, "Save & Complete Log" / "Just Log Once" |
| IMG_2425 | **Quick Log** (symptoms) | Logging time (Just Now / Edit Time), search custom symptoms, discomfort grid (Acid Reflux 🔥 Upper Gastric, Bloating 🎈 Abdomen, Abnormal Bowel 🚽 Lower GI, Nausea 🤢 Stomach, Skin Flare-ups 🔴 Dermatological, Headache 🤕 Neurological) each with intensity 1–5, tip banner, "Log Selected Instantly", "Advanced Settings & Timers" (duration, notes) |
| IMG_2426 | **History** (tab 2) | Month header + Digest button, week strip with colored dots (blue meal / green ok / orange symptom / dashed today), day chips, day summary (n entries, n flares, Add Log), meal cards (type, time, Logged / Suspicious Trigger badge, ingredients, edit/delete), symptom cards, "Review 7-Day Digest Summary" banner |
| IMG_2427 | **Weekly Health Digest — Trends** (tab 3) | Week pager, segmented Trends/Symptoms/Suspects, weekly average hero (index /10 vs all-time, discomfort-free days, severe peak day, meal log depth %), 7-bar chart with baseline line and zero/moderate/high colors, links to Suspects and Symptom cards, PDF button |
| IMG_2430/2431 | **Weekly Symptom Digest** | Total occurrences vs baseline, distribution bar, per-symptom cards (occurrences, % of week, avg severity /10, avg duration, peak day, top triggers), onset window distribution (<1h, 1–3h, 3h+ post-meal), Export PDF |
| IMG_2428/2429 | **Food Suspect Digest** | Top suspects hero (flares, meals evaluated, #1 suspect), symptom filter chips, 24h pre-flare ingredient frequency (top 5, x/y flares %, avg onset, times logged), pre-flare timing windows (0–4h / 4–12h / 12–24h), AI Pattern Synthesis card (text, "Add … to Watchlist", "Deep Breakdown"), suspect breakdown cards (exposures, meal→flare pairs, View Ingredient Profile, Track in Watchlist) |
| IMG_2432 | **Trigger Insights** (tab 4) | Symptom Rankings & Tiers banner, Ingredients / Cooking Styles segmented, symptom chips, empty state ("cards below 50% confidence are filtered"), Export Doctor Evidence Ledger (PDF) |
| IMG_2417/2418 | **User Profile** | Avatar, name, email, "Journaler for N days", Account Basics (display name, primary discovery purpose, sensitivity baseline tags), Ledger Export (Practitioner PDF, Raw CSV), Journal Preferences (Tracking rules & thresholds; Logging nudges & reminders), Account Actions (Clear local history, Sign out), Save |

Tab bar: Today · History · Digest · Triggers. Profile and notifications open from the Today header.

---

## Part 1 — Backend (`app/`)

### 1.1 Auth: Bearer tokens alongside cookie sessions

Keep the cookie session for the web. Add opaque Bearer tokens for iOS: revocable per device, Keychain-friendly, no silent 7-day expiry. Passport's `req.isAuthenticated()` is `!!req.user`, so a middleware that sets `req.user` from a token makes every existing `isAuthenticated` route work unchanged.

```ts
// app/shared/schema.ts
export const apiTokens = pgTable("api_tokens", {
  id: serial("id").primaryKey(),
  userId: varchar("user_id").notNull().references(() => users.id),
  tokenHash: varchar("token_hash", { length: 64 }).notNull().unique(), // sha256 hex
  deviceName: text("device_name"),
  createdAt: timestamp("created_at").defaultNow().notNull(),
  lastUsedAt: timestamp("last_used_at"),
  expiresAt: timestamp("expires_at"),   // default now()+180d, sliding
  revokedAt: timestamp("revoked_at"),
}, (t) => [index("IDX_api_tokens_user").on(t.userId)]);
```

Token = `tt_` + 32 random bytes base64url; only the sha256 is stored; `lastUsedAt` touched at most every 5 min. New `app/server/tokenAuth.ts` exports `bearerAuth` middleware, registered right after `setupAuth`.

| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/api/auth/register` | `{email,password,firstName?,lastName?,deviceName}` | 201 `{token, user}` |
| POST | `/api/auth/token` | `{email,password,deviceName}` | 200 `{token, user}`; 401 `{message}` |
| GET | `/api/auth/tokens` | – | `[{id,deviceName,createdAt,lastUsedAt}]` |
| DELETE | `/api/auth/token` | – | 204, revokes the calling token |
| DELETE | `/api/auth/tokens/:id` | – | 204 |
| GET | `/api/user` | – | unchanged; adds `displayName`, `createdAt` |

`/api/login`, `/api/register`, `/api/logout` are untouched.

### 1.2 Schema additions (all nullable or defaulted; safe for `drizzle-kit push`)

```ts
// users — additive
displayName: varchar("display_name"),
avatarEmoji: varchar("avatar_emoji"),
discoveryPurpose: text("discovery_purpose"),
sensitivityTags: json("sensitivity_tags").$type<string[]>().default([]),

export const userSettings = pgTable("user_settings", {
  userId: varchar("user_id").primaryKey().references(() => users.id),
  timezone: text("timezone").notNull().default("UTC"),        // IANA, set by iOS on launch
  correlationWindowHours: integer("correlation_window_hours").notNull().default(24),
  minTriggerCount: integer("min_trigger_count").notNull().default(2),
  minConfidence: integer("min_confidence").notNull().default(50),
  streakMealsPerDay: integer("streak_meals_per_day").notNull().default(2),
  nudgeTime: text("nudge_time").notNull().default("20:30"),    // local HH:mm
  nudgesEnabled: boolean("nudges_enabled").notNull().default(true),
  mealCheckInsEnabled: boolean("meal_check_ins_enabled").notNull().default(false),
  updatedAt: timestamp("updated_at").defaultNow(),
});

export type IngredientDetail = { name: string; cookMethod?: string | null };

export const dishes = pgTable("dishes", {            // saved dish tiles
  id: serial("id").primaryKey(),
  userId: varchar("user_id").notNull().references(() => users.id),
  name: text("name").notNull(),
  emoji: varchar("emoji").notNull().default("🍽️"),
  ingredients: json("ingredients").$type<IngredientDetail[]>().notNull().default([]),
  containsGluten/Dairy/Grains/Sugar/Nuts: boolean(...).default(false),
  timesLogged: integer("times_logged").notNull().default(0),
  lastLoggedAt: timestamp("last_logged_at"),
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
});

// meals — additive
ingredientDetails: json("ingredient_details").$type<IngredientDetail[]>(),  // null on legacy rows
dishId: integer("dish_id").references(() => dishes.id, { onDelete: "set null" }),
date: text("date").notNull().default(sql`to_char(now(), 'YYYY-MM-DD')`),

// symptoms — additive
intensity: integer("intensity"),            // 1..5
durationMinutes: integer("duration_minutes"),
catalogKey: text("catalog_key"),            // "acid_reflux" … or "custom:<slug>"
date: text("date").notNull().default(sql`to_char(now(), 'YYYY-MM-DD')`),

export const customSymptoms = pgTable("custom_symptoms", {
  id: serial("id").primaryKey(),
  userId: varchar("user_id").notNull().references(() => users.id),
  key: text("key").notNull(), name: text("name").notNull(),
  emoji: varchar("emoji").notNull().default("🩺"), bodyRegion: text("body_region"),
  createdAt: timestamp("created_at").defaultNow(),
}, (t) => [uniqueIndex("UQ_custom_symptoms").on(t.userId, t.key)]);

export const watchlist = pgTable("watchlist", {
  id: serial("id").primaryKey(),
  userId: varchar("user_id").notNull().references(() => users.id),
  ingredient: text("ingredient").notNull(),               // normalized lowercase
  source: text("source").notNull().default("manual"),     // manual | suspect | synthesis
  createdAt: timestamp("created_at").defaultNow(),
}, (t) => [uniqueIndex("UQ_watchlist").on(t.userId, t.ingredient)]);

// correlations — additive; old columns keep their meaning for the web
dimension: text("dimension").notNull().default("food"),   // food | ingredient | cook_method
exposures: integer("exposures").notNull().default(0),
flareExposures: integer("flare_exposures").notNull().default(0),
baselineRate: real("baseline_rate"), lift: real("lift"), avgOnsetHours: real("avg_onset_hours"),
windowHours: integer("window_hours"), lastFlareAt: timestamp("last_flare_at"),
updatedAt: timestamp("updated_at").defaultNow(),

export const aiSyntheses = pgTable("ai_syntheses", {
  id: serial("id").primaryKey(),
  userId: varchar("user_id").notNull().references(() => users.id),
  kind: text("kind").notNull(),               // "suspects_weekly"
  weekStart: text("week_start").notNull(),
  symptomFilter: text("symptom_filter"),
  inputHash: varchar("input_hash", { length: 64 }).notNull(),
  source: text("source").notNull(),           // "claude" | "rules"
  model: text("model"), text: text("text").notNull(),
  createdAt: timestamp("created_at").defaultNow(),
}, (t) => [uniqueIndex("UQ_ai_synth").on(t.userId, t.kind, t.weekStart, t.symptomFilter)]);
```

Zod: `insertSymptomSchema` picks `timestamp, intensity, durationMinutes, catalogKey` too; `insertMealSchema` adds `ingredientDetails, dishId`; new `updateMealSchema = insertMealSchema.omit({userId:true}).partial()` and `updateSymptomSchema`; new `insertDishSchema`, `insertCustomSymptomSchema`, `settingsPatchSchema`, `profilePatchSchema`.

Shared constants, mirrored in Swift:
- `app/shared/symptomCatalog.ts` — the six default symptoms with key, name, emoji, body region.
- `app/shared/cookMethods.ts` — raw, grilled, fried, deep_fried, baked, roasted, boiled, steamed, sauteed, smoked, fermented, processed, toasted.
- `app/shared/severity.ts` — intensity→severity: 1–2 Mild, 3 Moderate, 4–5 Severe; severity→intensity (web writes): Mild 2, Moderate 3, Severe 4; discomfort score /10 = intensity × 2 (mockup: Level 3 → 6.0/10). The server always stores both; the web keeps using `severity`.

### 1.3 Bug fixes the iOS app would hit (M0)

| Bug | Fix |
|---|---|
| `POST /api/symptoms` drops client `timestamp` (not picked by `insertSymptomSchema`) | pick it; convert ISO string → Date in the route as meals already do (`routes.ts:174-180`) |
| `PUT /api/symptoms/:id` 500s on ISO timestamp | same conversion + `updateSymptomSchema.parse` |
| IDOR: `/api/meals/:id`, `/api/symptoms/:id` never check ownership | add `userId` param to get/update/delete in `storage.ts` + `database-storage.ts` (`where(and(eq(id), eq(userId)))`); 404 when not owned |
| PUT bodies unvalidated | `updateMealSchema` / `updateSymptomSchema`, 400 on ZodError |
| `updateMeal` overwrites `ingredients` from `notes` (`database-storage.ts:123-131`) | remove derivation on update (keep on create only when `ingredients` absent); when `ingredientDetails` is sent, set `ingredients = ingredientDetails.map(i => i.name)` so the web sees the same list |
| `date` default evaluated at module load; create forces UTC "today" | DB default `to_char(now(),'YYYY-MM-DD')`; storage derives `date` from `timestamp` in the request `tz` or `user_settings.timezone` (`date-fns-tz`) |
| Correlations recomputed synchronously inside `createSymptom` | `analytics/scheduler.ts`: per-user 3 s debounce after any meal/symptom/settings write; responses return first |

### 1.4 Endpoints (dependency order; all `isAuthenticated`, cookie or Bearer)

Day-bucketed endpoints accept `tz=<IANA>` (default `user_settings.timezone`). Dates are local `YYYY-MM-DD`; timestamps ISO-8601 UTC.

**Profile & settings (M0)**

| Method | Path | Body / Query | Response |
|---|---|---|---|
| GET | `/api/profile` | – | `{id,email,firstName,lastName,displayName,avatarEmoji,discoveryPurpose,sensitivityTags,createdAt,journalerDays,firstLogAt}` |
| PATCH | `/api/profile` | subset of the editable fields | profile |
| GET | `/api/settings` | – | settings row (auto-created) |
| PATCH | `/api/settings` | subset | settings; window/threshold changes schedule a recompute |

**Symptoms (M0/M3)**

| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/api/symptoms` | `{name,catalogKey?,intensity?(1-5),severity?,timestamp?,tz?,durationMinutes?,notes?}` (intensity or severity required) | 201 Symptom (+`intensity,durationMinutes,catalogKey,emoji,bodyRegion`) |
| POST | `/api/symptoms/batch` | `{timestamp,tz?,durationMinutes?,notes?,items:[{name,catalogKey?,intensity}]}` | 201 `Symptom[]`, one recompute |
| PUT | `/api/symptoms/:id` | validated partial | Symptom |
| GET | `/api/symptom-catalog` | – | `{defaults:[…],custom:[…]}` |
| POST / DELETE | `/api/symptom-catalog[/:id]` | `{name,emoji?,bodyRegion?}` | 201 / 204 |

**Meals & dishes (M2)**

| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/api/meals` | existing + `ingredientDetails:[{name,cookMethod}]`, `dishId?`, `tz?` | 201 Meal |
| GET / POST | `/api/dishes` | `{name,emoji,ingredients:[{name,cookMethod}],contains*}` | `Dish[]` (by `lastLoggedAt desc, timesLogged desc`) / 201 |
| PUT / DELETE | `/api/dishes/:id` | partial | Dish / 204 |
| POST | `/api/dishes/:id/log` | `{mealType,timestamp,tz?,overrides?:{ingredientDetails?}}` | 201 Meal; bumps `timesLogged`, `lastLoggedAt` |

**Entries (M1, additive fields)**
- `GET /api/entries/date?date&tz` → `{date, meals:[Meal & {suspiciousFor:[…], suspicion:"window"|"correlated"|null}], symptoms:[…], flares, entries}`
- `GET /api/entries/markers?start&end&tz` → `{"2026-09-11":{meals:2,symptoms:1,maxIntensity:3,status:"symptom"|"ok"|"meal"}}` (week-strip dot colors)
- `GET /api/entries/recent` unchanged (web only).

**Coverage (M3)** — `GET /api/coverage?date=2026-09-17&tz=America/Los_Angeles`
```json
{"date":"2026-09-17",
 "slots":{"Breakfast":{"logged":true,"mealId":41,"time":"08:15"},"Lunch":{"logged":true,"mealId":42,"time":"12:45"},"Dinner":{"logged":false}},
 "loggedCount":2,"slotTotal":3,"percent":67,
 "streak":{"days":5,"threshold":2,"rule":"2+ meals/day","todayCounts":true},
 "week":[{"date":"2026-09-11","weekday":"Fri","meals":1,"slotsLogged":1,"metThreshold":false}],
 "weekSlots":{"logged":9,"total":21,"bySlot":{"Breakfast":{"logged":4,"total":7},"Lunch":{"logged":3,"total":7},"Dinner":{"logged":2,"total":7}}},
 "nudge":{"time":"20:30","enabled":true}}
```
Slot = `meal.mealType` (Snack ignored for coverage). Streak = consecutive days ending today (or yesterday if today isn't met yet) with `meals >= streakMealsPerDay`.

**Weekly digest (M4)** — `GET /api/digest/weekly?weekStart=2026-09-11&tz=…` (7-day window from any start day)
```json
{"weekStart":"2026-09-11","weekEnd":"2026-09-17","previousWeekStart":"2026-09-04","hasNextWeek":false,
 "trends":{"index":1.7,"baselineIndex":1.7,"deltaVsBaselinePercent":0,"previousWeekIndex":2.2,"changeVsPreviousPercent":-22,
   "occurrences":4,"flares":2,"discomfortFreeDays":5,"severeDays":0,"severePeakDay":"2026-09-11","mealLogDepth":0.10,"dataCompleteness":"complete",
   "days":[{"date":"2026-09-11","weekday":"Fri","index":6,"occurrences":2,"maxIntensity":3,"level":"high"}]},
 "symptoms":{"total":4,"baselinePerWeek":4.0,"vsBaseline":"same","distinct":2,
   "distribution":[{"name":"Acid Reflux","catalogKey":"acid_reflux","count":2,"share":0.5}],
   "cards":[{"name":"Acid Reflux","catalogKey":"acid_reflux","emoji":"🔥","occurrences":2,"shareOfWeek":0.5,"avgSeverity10":6.0,"avgDurationMinutes":60,"peakDay":"2026-09-11","vsBaseline":"same","topTriggers":["sourdough bread","avocado","salt"]}],
   "onsetWindows":{"under1h":2,"from1to3h":1,"over3h":1,"unmatched":0}}}
```
Definitions: daily index = `max(intensity) × 2` for the local day (0 if none); weekly index = mean of 7 daily indexes; baseline = mean daily index since first log; `level` 0 → zero, 1–4 → moderate, ≥5 → high; meal log depth = logged B/L/D slots ÷ 21; onset window = hours from the most recent prior meal (within `correlationWindowHours`); a **flare** = cluster of symptoms within 30 min of the cluster start (mockup: 2 flares, 4 occurrences).

**Suspects digest (M4)** — `GET /api/digest/suspects?weekStart&symptom=Acid%20Reflux&tz`
```json
{"weekStart":"2026-09-11","weekEnd":"2026-09-17","windowHours":24,"flares":2,"mealsEvaluated":2,"leadSuspect":"sourdough bread",
 "symptomFilters":[{"name":"All Symptoms","count":2},{"name":"Acid Reflux","count":2},{"name":"Bloating","count":2}],
 "ingredients":[{"name":"sourdough bread","flaresWithIngredient":1,"flaresTotal":2,"share":0.5,"avgOnsetHours":1.7,"timesLoggedThisWeek":1,"exposuresAllTime":6,"confidence":38,"onWatchlist":false,
   "recentPairs":[{"mealId":12,"mealName":"Avocado Sourdough Toast","mealAt":"2026-09-11T19:45:00Z","flareAt":"2026-09-11T21:29:00Z","symptoms":["Acid Reflux","Bloating"],"onsetHours":1.7}]}],
 "timingWindows":{"0to4h":{"flares":2,"topIngredients":["sourdough bread","avocado","salt"]},"4to12h":{"flares":0,"topIngredients":[]},"12to24h":{"flares":0,"topIngredients":[]}}}
```
Top 5 by `share`, then `confidence`.

**Trigger insights (M4)** — `GET /api/insights/triggers?dimension=ingredient|cook_method&symptom=&minConfidence=50`
```json
{"dimension":"ingredient","minConfidence":50,"windowHours":24,
 "symptoms":[{"name":"Headache","emoji":"🤕","count":3}],
 "cards":[{"item":"sourdough bread","dimension":"ingredient","symptomName":"Acid Reflux","confidence":72,"tier":"likely","exposures":6,"flareExposures":4,"hitRate":0.67,"baselineRate":0.2,"lift":3.3,"avgOnsetHours":1.9,"lastFlareAt":"…",
   "evidence":[{"mealId":12,"mealName":"…","mealAt":"…","symptomAt":"…","onsetHours":1.7}]}],
 "hiddenBelowThreshold":3}
```
`GET /api/correlations` (web) keeps its shape.

**Watchlist (M5)** — `GET /api/watchlist` → `[{id,ingredient,source,createdAt,confidenceMax}]`; `POST /api/watchlist {ingredient,source?}` 201; `DELETE /api/watchlist/:id` 204. Matching during meal entry happens on device against the cached list (lowercase substring), no round trip.

**AI synthesis (M5)** — `POST /api/ai/synthesis {weekStart, symptom?, tz?}` → `{text, source:"claude"|"rules", model, cached, generatedAt, suggestedWatchlist:[…]}`.
`app/server/ai/synthesis.ts`: build the suspects payload → `inputHash = sha256(canonical JSON)` → look up `ai_syntheses` by `(user, kind, weekStart, symptomFilter)`; hit if the hash matches (unchanged data ⇒ no regeneration, no TTL). On miss with `ANTHROPIC_API_KEY` set, use `@anthropic-ai/sdk`:
```ts
const res = await client.messages.create({
  model: "claude-opus-5",
  max_tokens: 600,
  output_config: { effort: "low" },
  betas: ["server-side-fallback-2026-07-01"], fallbacks: "default",
  system: SYNTHESIS_SYSTEM, // non-diagnostic; cite only numbers in the JSON; ≤ 90 words; no elimination advice
  messages: [{ role: "user", content: JSON.stringify(payload) }],
});
if (res.stop_reason === "refusal") return rulesSynthesis(payload);
const text = res.content.filter(b => b.type === "text").map(b => b.text).join("");
```
`rulesSynthesis(payload)` produces template prose (e.g. "In the 24-hour lookback before flares, sourdough bread appeared in 1 of 2 flare windows (50%), with an average meal-to-flare delay of 1.7 hours. These are observed associations rather than proof of a trigger…") and is also used on any API error or 8 s timeout. Rate limit: one generation per user per 30 s. Fewer than one flare ⇒ "Not enough flares yet".

**Exports (M6)** — server CSV, on-device PDFs:
- `GET /api/export/csv?from&to&tz` → `text/csv` attachment with columns `entry_type,id,date,time,name,meal_type,ingredients,cook_methods,dish,intensity,severity,duration_minutes,notes,timestamp_utc`.
- `GET /api/export/ledger?from&to&tz` → `{profile,settings,range,days:[{date,meals,symptoms,flares}],triggers,digestWeeks:[…]}`, consumed by the iOS PDF renderers (Practitioner Report, Doctor Evidence Ledger). The weekly digest PDF renders from the already-loaded digest JSON. No PDF library on the server.

"Clear Local Journal History" wipes the on-device cache only. A server-side purge is an open question (see below).

### 1.5 Correlation engine v2 (`app/server/analytics/correlations.ts`, pure functions + tests)

Inputs: the user's meals and symptoms, settings `{correlationWindowHours: W, minTriggerCount}`.
1. Items per meal: `ingredient` = `ingredientDetails[].name` ?? `ingredients[]` ?? `parseMealIntoFoods(name)` (existing helper, moved to `analytics/foods.ts`), lowercased/trimmed; `cook_method` = distinct `ingredientDetails[].cookMethod`. Keep a display-casing map.
2. For meal `m` and symptom name `s`: `followed(m,s)` = a symptom `s` exists with `0 < t_s − t_m ≤ W`. Baseline `b_s = |{m : followed(m,s)}| / |meals|`.
3. Per `(item, dimension, s)`: `E` = meals containing the item; `F` = those with `followed`; `hitRate = F/E`; `lift = hitRate / b_s` (capped at 5 when `b_s = 0`); `avgOnsetHours`; `lastFlareAt`.
4. Confidence 0–100: `support = 1 − e^(−F/2)`; `liftFactor = clamp(lift/2, 0, 1)`; `confidence = round(100 · hitRate · support · (0.5 + 0.5·liftFactor))`, minus 10 for `cook_method`. Rows with `E < 2` or `F < minTriggerCount` are stored but capped at 49 so they never pass the default 50 % filter. Tiers: ≥ 75 strong, 50–74 likely, 25–49 watch.
5. Persist in one transaction: delete the user's rows, bulk insert. Legacy columns filled for the web: `foodName = item`, `occurrences = F`, `isIngredient = dimension !== "food"`; `dimension:"food"` rows still come from `parseMealIntoFoods(name)` so the web Insights page keeps showing whole-food rows.
6. Triggered by the debounced scheduler after any meal/symptom/settings write; `POST /api/correlations/regenerate` runs it immediately.
7. **Suspicious Trigger** (derived, not stored): a meal is suspicious if any symptom occurred within `(0, W]` hours after it (`suspicion:"window"`), upgraded to `"correlated"` if one of its items has a correlation ≥ `minConfidence` for one of those symptoms.

Other pure modules: `analytics/time.ts` (tz day bucketing, week ranges), `analytics/flares.ts` (30-min clustering, onset deltas), `analytics/coverage.ts`, `analytics/digest.ts`, `analytics/suspects.ts`. Routes stay thin. `routes.ts` is split into `app/server/routes/{index,auth,meals,symptoms,dishes,profile,coverage,digest,insights,watchlist,ai,export}.ts`.

New deps: `@anthropic-ai/sdk`, `date-fns-tz`; dev: `vitest`, `supertest`. Railway env: `ANTHROPIC_API_KEY` (optional), add `ANTHROPIC_API_KEY: preserve()` to `.railway/railway.ts`.

---

## Part 2 — iOS app (`ios/`)

### 2.1 Machine setup

1. App Store → install **Xcode** (~15 GB); launch once; `sudo xcodebuild -license accept`.
2. `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer && xcodebuild -runFirstLaunch`
3. Simulator runtime: `xcodebuild -downloadPlatform iOS`; verify with `xcrun simctl list devices available`.
4. `brew install xcodegen` (optionally `swiftlint`, `swiftformat`).
5. `cd ios && xcodegen generate && open TasteTrace.xcodeproj` — `*.xcodeproj` is git-ignored; `project.yml` is the source of truth.
6. CLI: `xcodebuild -project ios/TasteTrace.xcodeproj -scheme TasteTrace -destination 'platform=iOS Simulator,name=iPhone 16' build` (or `test`).
7. Signing: `CODE_SIGN_STYLE=Automatic`, `DEVELOPMENT_TEAM` empty; the simulator needs no team. A free Apple ID allows 7-day device installs; the paid Developer Program is needed only for TestFlight/App Store.

**Validatable today without Xcode:** `swift build` / `swift test` inside each `ios/Packages/*` package. They declare `platforms: [.iOS(.v17), .macOS(.v14)]` and avoid UIKit (UIKit-only code such as `UIGraphicsPDFRenderer` and notification wiring lives in the app target or behind `#if canImport(UIKit)`), so the API client, models, view models, domain math and design tokens compile and test on the command line. The app target, simulator runs and previews need Xcode.

### 2.2 Project layout (XcodeGen `ios/project.yml`)

```
ios/
  project.yml                      # targets: TasteTrace (iOS 17.0), TasteTraceTests; links the local packages
  Config/Debug.xcconfig            # API_BASE_URL = http://localhost:5000
  Config/Release.xcconfig          # API_BASE_URL = https://tastetrace-app.up.railway.app
  TasteTrace/
    App/  TasteTraceApp.swift (@main), AppEnvironment.swift (APIClient, AuthSession, repositories, ReminderScheduler),
          RootView.swift (signed-out → Auth; signed-in → MainTabView), MainTabView.swift (4 tabs, NavigationStack each), Router.swift (Route + AppSheet enums)
    Resources/  Assets.xcassets, PrivacyInfo.xcprivacy, Localizable.xcstrings
    Features/
      Auth/          SignInView, SignUpView, AuthViewModel
      Today/         TodayView, TodayViewModel, DigestHeroCard, CoverageCard, TimelineSection, StatusToast
      Coverage/      CoverageView, CoverageViewModel, StreakHero, CoverageWheel, WeekBreakdown
      LogMeal/       LogMealFlow (NavigationStack in fullScreenCover), LogMealStep1View, DishTileRow, DishLibraryView,
                     VerifyIngredientsView, IngredientRow, CookMethodPicker, TriggerTracesCard, SaveDishSheet, EditDishView, LogMealViewModel
      QuickLog/      QuickLogView, QuickLogViewModel, SymptomGridCard, IntensitySelector, AdvancedSymptomSettingsView, CustomSymptomSearch
      History/       HistoryView, HistoryViewModel, WeekStrip, DayChips, DaySummaryCard, MealEntryCard, SymptomEntryCard, EditMealView, EditSymptomView, JumpToDateSheet
      Digest/        DigestView (week pager + segmented), TrendsView, SymptomsDigestView, SuspectsDigestView, DigestViewModel, SuspectsViewModel,
                     SynthesisCard, SuspectCard, TimingWindowsCard
      Triggers/      TriggerInsightsView, TriggerInsightsViewModel, TriggerCard, TriggerEmptyState
      Watchlist/     WatchlistView, WatchlistViewModel
      Profile/       ProfileView, ProfileViewModel, TrackingRulesView, RemindersView, SensitivityTagsSheet
      Notifications/ NotificationsView, ReminderScheduler (UNUserNotificationCenter)
      Export/        PDFDocumentBuilder (UIGraphicsPDFRenderer), WeeklyDigestPDF, EvidenceLedgerPDF, PractitionerReportPDF, ExportViewModel (ShareLink)
  TasteTraceTests/                 # app-level VM tests + one XCUITest smoke (need Xcode)
  Packages/
    TasteTraceAPI/   APIClient, Transport (protocol), URLSessionTransport, APIError, TokenProvider, JSONCoding (ISO8601 w/ fractional seconds)
                     Endpoints/ AuthAPI, MealsAPI, SymptomsAPI, DishesAPI, EntriesAPI, CoverageAPI, DigestAPI, InsightsAPI, WatchlistAPI, ProfileAPI, AIAPI, ExportAPI
                     Models/ User, Settings, Meal, IngredientDetail, Symptom, Dish, DayEntries, Markers, Coverage, WeeklyDigest, SuspectsDigest,
                             TriggerInsights, WatchlistItem, Synthesis, SymptomCatalog, LedgerBundle
                     Tests/ + Fixtures/*.json captured from curl
    TasteTraceCore/  (depends on TasteTraceAPI)
                     Session/AuthSession (@Observable), Keychain/KeychainTokenStore
                     Cache/ CacheContainer (SwiftData), CachedMeal, CachedSymptom, CachedDish, CachedWatchlistItem, CachedSettings
                     Repositories/ Meal, Symptom, Dish, Watchlist, Insights, Profile  (API-first, write-through cache, cache when offline)
                     Domain/ SymptomCatalog, CookMethod, MealSlot, DateMath, WatchlistMatcher, DiscomfortIndex, SeverityMapping
    TasteTraceUI/    Theme/ TTColor, TTTypography, TTRadius, TTSpacing, TTGradient
                     Components/ TTCard, HeroGradientCard, TTChip, StatusBadge, PrimaryButton, SecondaryButton, PinnedBottomBar, RingProgress,
                                 TTSegmentedControl, EmojiCircle, WeekDots, SectionLabel, InfoBanner, DashedPlaceholderCard, ToastView
                     Charts/ DiscomfortBarChart (Swift Charts), SparklineView, DistributionBar, FrequencyBar
```

Stack: iOS 17+, SwiftUI, `@Observable` view models, async/await, `URLSession`, `Codable` mirrors of the API, Keychain token, a JSON-file read cache (`JSONFileStore`) synced on load (writes online-only through M5; an offline write queue is a stretch), Swift Charts, UserNotifications, `UIGraphicsPDFRenderer` + `ShareLink`. Barcode scanning (AVFoundation) is a stretch after M6.

Implementation notes (M1): SwiftData's `@Model` macro and XCTest are not available in the command-line toolchain, so the cache uses plain JSON files and package tests are XCTest files that run once Xcode is installed. All screens live in `Packages/TasteTraceFeatures` (UIKit-free) so `swift build` validates them here; the app target is a thin `@main` shell. `Packages/TasteTraceAPI` also has an `apismoke` executable that exercises the real client against a running backend.

### 2.3 Design tokens (from the mockups)

- Colors: background `#F3F6FC`; card `#FFFFFF` with 1 pt border `#DCE5F5`; primary `#2563EB`; navy text `#1B2559`; secondary text `#5B6B8C`; hero gradient `#1E2A4A → #2B63D9`; dark toast `#22304F`; success `#16A34A` on `#E8F8EF`; warning `#F59E0B` on `#FFF6E5` (watchlist card border `#F8C98A`); danger `#DC2626` on `#FEE9E9`; info tint `#E8F0FE`.
- Radii: card 20, inner tile 16, button 16 (pinned CTA 20), chip 999, ring stroke 8.
- Type (SF Pro): hero number 40 bold rounded; screen title 24 bold; card title 18 semibold; body 16; caption 13; section label 13 semibold uppercase, tracking 1.2, secondary color.
- Emoji as icons throughout. Primary CTA pinned above the tab bar via `safeAreaInset(edge: .bottom)`; segmented pill control; week-strip dots (blue meal / green ok / orange symptom / dashed today); status toast at the bottom of Today.

### 2.4 Screen → files → endpoints

| Mockup | View (+VM) | Endpoints |
|---|---|---|
| 2419 Today | `TodayView`, `DigestHeroCard`, `CoverageCard`, `TimelineSection` | `GET /api/digest/weekly` (current week), `GET /api/coverage?date=today`, `GET /api/entries/date?date=today`, `GET /api/user` |
| 2420 Coverage | `CoverageView` | `GET /api/coverage`, `GET /api/settings` |
| 2421/2422 Log a Meal | `LogMealFlow`, `LogMealStep1View`, `DishTileRow`, `DishLibraryView` | `GET /api/dishes`, `PUT/DELETE /api/dishes/:id`, `POST /api/dishes/:id/log` (tile tap = instant log) |
| 2423 Verify Ingredients | `VerifyIngredientsView`, `IngredientRow`, `CookMethodPicker`, `TriggerTracesCard` | local `WatchlistMatcher` over cached `GET /api/watchlist`; `POST /api/meals` |
| 2424 Save dish | `SaveDishSheet` | `POST /api/dishes` then `POST /api/meals` with `dishId` |
| 2425 Quick Log | `QuickLogView`, `SymptomGridCard`, `AdvancedSymptomSettingsView` | `GET/POST /api/symptom-catalog`, `POST /api/symptoms/batch` |
| 2426 History | `HistoryView`, `WeekStrip`, `DayChips`, entry cards, `EditMealView`, `EditSymptomView` | `GET /api/entries/markers`, `GET /api/entries/date`, `PUT/DELETE /api/meals/:id`, `PUT/DELETE /api/symptoms/:id` |
| 2427 Trends | `DigestView`, `TrendsView`, `DiscomfortBarChart` | `GET /api/digest/weekly?weekStart` |
| 2430/2431 Symptoms digest | `SymptomsDigestView` | same payload, `symptoms` section |
| 2428/2429 Suspects | `SuspectsDigestView`, `SynthesisCard`, `SuspectCard`, `TimingWindowsCard` | `GET /api/digest/suspects`, `POST /api/ai/synthesis`, `POST /api/watchlist` |
| 2432 Triggers | `TriggerInsightsView`, `TriggerCard`, `TriggerEmptyState` | `GET /api/insights/triggers`, `GET /api/settings` |
| 2417/2418 Profile | `ProfileView`, `TrackingRulesView`, `RemindersView` | `GET/PATCH /api/profile`, `GET/PATCH /api/settings`, `DELETE /api/auth/token`, `GET /api/export/csv`, `GET /api/export/ledger` |
| Bell | `NotificationsView`, `ReminderScheduler` | local notifications from `settings.nudgeTime`; pending-slot reminders derived from `/api/coverage` |

Navigation: `MainTabView` → four `NavigationStack`s with per-tab `Router` paths; sheets/covers from one `AppSheet` enum (`logMeal`, `quickLog(date:)`, `saveDish`, `profile`, `notifications`, `jumpToDate`). "View Report" / "Review 7-Day Digest" switch to the Digest tab with a `weekStart`; "Go to History" switches tab.

### 2.5 Testing

- Packages (`swift test`, works now): `MockTransport` returns fixture JSON per path → decoding tests for every model; `AuthSession` with an in-memory token store; domain tests (`DiscomfortIndex`, `DateMath` week ranges/tz, `WatchlistMatcher`, `SeverityMapping`); view-model tests through a fake API (e.g. `LogMealViewModel` builds the right `POST /api/meals` body; `QuickLogViewModel` batches selected symptoms).
- App target (Xcode): the same VM tests plus one XCUITest smoke (sign in → log a meal → see it in History) in M6.
- Backend: `vitest` for `analytics/*` with fixtures reproducing the mockup numbers; `supertest` for auth and ownership checks; `npm run check` (tsc).

---

## Part 3 — Milestones

Local backend for every milestone:
```sh
docker run --name tastetrace-pg -e POSTGRES_PASSWORD=pg -e POSTGRES_DB=tastetrace -p 5432:5432 -d postgres:16
cd app && export DATABASE_URL=postgres://postgres:pg@localhost:5432/tastetrace SESSION_SECRET=dev
npm install && npm run db:push && npm run dev      # http://localhost:5000
```

### M0 — Backend foundations + auth (deployable; web unaffected)
Files: `app/shared/schema.ts` (api_tokens, user_settings, profile columns, symptom intensity/duration/catalogKey, meal ingredientDetails/dishId, date defaults, update schemas); new `app/shared/{symptomCatalog,cookMethods,severity}.ts`; new `app/server/tokenAuth.ts`; `app/server/auth.ts` (bearer middleware, `/api/user` additive fields); `app/server/storage.ts` + `database-storage.ts` (ownership params, tz-aware `date`, severity↔intensity fill, remove notes→ingredients on update, settings/profile CRUD); split `routes.ts` into `app/server/routes/*`; `app/server/analytics/{time,scheduler}.ts`; `app/package.json`; README.
Verify:
```sh
TOKEN=$(curl -s -X POST localhost:5000/api/auth/register -H 'content-type: application/json' -d '{"email":"a@b.co","password":"pw12345","deviceName":"curl"}' | jq -r .token)
curl -s localhost:5000/api/user -H "authorization: Bearer $TOKEN"                                  # 200 incl. displayName
curl -s -X POST localhost:5000/api/symptoms -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"name":"Acid Reflux","catalogKey":"acid_reflux","intensity":3,"timestamp":"2026-09-11T21:29:00Z","tz":"America/Los_Angeles","durationMinutes":60}'   # severity Moderate, date 2026-09-11
curl -s -X PUT localhost:5000/api/symptoms/1 -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' -d '{"timestamp":"2026-09-11T22:00:00Z"}'   # 200, not 500
curl -s -X POST localhost:5000/api/symptoms -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' -d '{"name":"x","intensity":9}'   # 400
# second user: PUT/DELETE /api/symptoms/1 and /api/meals/<id> → 404
curl -s -X PATCH localhost:5000/api/settings -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' -d '{"timezone":"America/Los_Angeles"}'
curl -s -X DELETE localhost:5000/api/auth/token -H "authorization: Bearer $TOKEN" -o /dev/null -w '%{http_code}\n'   # 204; then /api/user → 401
cd app && npm run check && npx vitest run
# Web regression in the browser: log in, log a meal and a symptom (severity only), edit a meal, Insights still lists correlations.
```

### M1 — iOS skeleton, auth, Today/History on existing data
Files: `ios/project.yml`, `ios/Config/*.xcconfig`, `ios/.gitignore` (`*.xcodeproj`, `xcuserdata`, `.build`), the three packages with `Package.swift`, `TasteTraceUI/Theme` + `Components`, `TasteTraceAPI` (client, transport, Auth/Entries/Meals/Symptoms endpoints, User/Meal/Symptom/DayEntries/Markers models), `TasteTraceCore` (AuthSession, KeychainTokenStore, CacheContainer, CachedMeal/CachedSymptom, Meal/Symptom repositories, DateMath), `App/*`, `Features/Auth`, `Features/Today` (coverage card placeholder until M3; hero "Not enough data" until M4), `Features/History` incl. edit/delete.
Verify: `cd ios/Packages/TasteTraceAPI && swift test`; `xcodegen generate`; `xcodebuild … test`; simulator: sign up → Today → History shows the M0 symptom on Sep 11 with an orange dot → delete it → list refreshes; relaunch stays signed in (Keychain); with the server stopped the cached day still renders.

### M2 — Log Meal flow, saved dishes, ingredients + cook methods
Backend: `schema.ts` (dishes + `insertDishSchema`), `routes/dishes.ts`, `database-storage.ts` (dish CRUD, `logDish`, ingredientDetails→ingredients sync), meals route accepts `ingredientDetails`/`dishId`.
iOS: `Features/LogMeal/*`, `DishesAPI`, `Dish`/`IngredientDetail` models, `DishRepository`, `CookMethod`, `CachedDish`; `MealEntryCard` shows ingredients.
Verify:
```sh
curl -s -X POST localhost:5000/api/dishes -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' -d '{"name":"Avocado Sourdough Toast","emoji":"🥑","ingredients":[{"name":"sourdough bread","cookMethod":"toasted"},{"name":"avocado","cookMethod":"raw"},{"name":"salt"}],"containsGluten":true}'
curl -s -X POST localhost:5000/api/dishes/1/log -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' -d '{"mealType":"Lunch","timestamp":"2026-09-11T19:45:00Z","tz":"America/Los_Angeles"}'   # 201, ingredients ["sourdough bread","avocado","salt"], dishId 1
curl -s localhost:5000/api/meals -H "authorization: Bearer $TOKEN" | jq '.[0].ingredientDetails'
```
Simulator: Log Meal → Lunch → Write New Recipe → Verify Ingredients (comma input adds chips, per-row cook method) → Complete → Save dish → History shows the meal; reopen Log Meal → tile present → tap logs instantly. Web app still shows the meal with its ingredient list.

### M3 — Quick Log symptoms + coverage/streak
Backend: `analytics/coverage.ts`, `routes/coverage.ts`, `/api/symptoms/batch`, `/api/symptom-catalog`, vitest for streak rules.
iOS: `Features/QuickLog/*`, `Features/Coverage/*`, `CoverageCard` wired, `CoverageAPI`, `Coverage`/`SymptomCatalog` models, `MealSlot`.
Verify:
```sh
curl -s -X POST localhost:5000/api/symptoms/batch -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' -d '{"timestamp":"2026-09-11T21:29:00Z","tz":"America/Los_Angeles","items":[{"name":"Acid Reflux","catalogKey":"acid_reflux","intensity":3},{"name":"Bloating","catalogKey":"bloating","intensity":1}]}'   # 201, 2 symptoms
curl -s "localhost:5000/api/coverage?date=2026-09-11&tz=America/Los_Angeles" -H "authorization: Bearer $TOKEN" | jq '.loggedCount,.streak,.weekSlots.logged'
```
Simulator: Quick Log → tap two cards with intensities → Log Selected Instantly → toast; Edit Time backdates; coverage ring shows 1/3; streak text matches the rule; 7-day breakdown x/21.

### M4 — Digest (Trends/Symptoms/Suspects), correlations v2, Trigger Insights, Suspicious badge
Backend: `analytics/{flares,foods,correlations,digest,suspects}.ts`, `routes/{digest,insights}.ts`, `database-storage.ts` (`replaceCorrelations` transaction; scheduler replaces inline `analyzeCorrelations`; `regenerateCorrelations` delegates), correlation columns, entries endpoints add `suspiciousFor`, vitest fixtures reproducing the mockup numbers (Fri 6, six zeros → index 1.7).
iOS: `Features/Digest/*`, `Features/Triggers/*`, `TasteTraceUI/Charts/*`, `DigestAPI`/`InsightsAPI`, digest models, `DigestHeroCard` wired, `MealEntryCard` badge.
Verify:
```sh
curl -s -X POST localhost:5000/api/correlations/regenerate -H "authorization: Bearer $TOKEN"
curl -s "localhost:5000/api/digest/weekly?weekStart=2026-09-11&tz=America/Los_Angeles" -H "authorization: Bearer $TOKEN" | jq '.trends.index,.trends.days[0],.symptoms.cards[0]'
curl -s "localhost:5000/api/digest/suspects?weekStart=2026-09-11&tz=America/Los_Angeles" -H "authorization: Bearer $TOKEN" | jq '.flares,.ingredients[0]'
curl -s "localhost:5000/api/insights/triggers?dimension=ingredient&minConfidence=0" -H "authorization: Bearer $TOKEN" | jq '.cards[0]'
curl -s "localhost:5000/api/entries/date?date=2026-09-11&tz=America/Los_Angeles" -H "authorization: Bearer $TOKEN" | jq '.meals[0].suspiciousFor'   # ["Acid Reflux","Bloating"]
curl -s localhost:5000/api/correlations -H "authorization: Bearer $TOKEN"   # web shape intact
```
Simulator: Digest pages weeks; bars colored by level with baseline line; Symptoms cards show 6.0/10, ~1 hour, Friday; Suspects shows 1/2 flares (50 %), 1.7 h onset, 0–4 h window = 2; Triggers shows the empty state until a card reaches 50 % (lower the threshold in settings to see cards); History lunch card shows "Suspicious Trigger".

### M5 — Watchlist, AI synthesis, profile/settings, reminders
Backend: `schema.ts` (watchlist, ai_syntheses), `routes/{watchlist,ai}.ts`, `app/server/ai/{synthesis,rules}.ts`, `@anthropic-ai/sdk`, Railway `ANTHROPIC_API_KEY`.
iOS: `Features/Watchlist/*`, `Features/Profile/*`, `Features/Notifications/*` (`ReminderScheduler`: daily nudge at `settings.nudgeTime`; optional meal check-ins at 09:30/13:30/19:30 cancelled once the slot is logged), `SynthesisCard`, real `TriggerTracesCard` matching, `WatchlistAPI`/`ProfileAPI`/`AIAPI`, `CachedWatchlistItem`, `PrivacyInfo.xcprivacy`.
Verify:
```sh
curl -s -X POST localhost:5000/api/watchlist -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' -d '{"ingredient":"Sourdough Bread","source":"suspect"}'   # stored lowercase
curl -s -X POST localhost:5000/api/ai/synthesis -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' -d '{"weekStart":"2026-09-11","tz":"America/Los_Angeles"}' | jq '.source,.cached,.text'   # "rules" without key, "claude" with; second call cached:true
curl -s -X PATCH localhost:5000/api/profile -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' -d '{"displayName":"Taylor Josephson","sensitivityTags":["gluten"]}'
```
Simulator: Verify Ingredients shows "Watchlist Alert" for a matched ingredient; Suspects "Add … to Watchlist" toggles; Profile edits persist, "Journaler for N days" correct; changing the tracking window recomputes Triggers; reminders fire (set nudge to now + 2 min, background the app); Sign out revokes the token (`GET /api/auth/tokens` no longer lists the device).

### M6 — Exports, polish, optional TestFlight
Backend: `routes/export.ts` (`/api/export/csv`, `/api/export/ledger`).
iOS: `Features/Export/*` (three PDF builders on `UIGraphicsPDFRenderer`, `ShareLink`), CSV download → `ShareLink`; empty states, haptics, accessibility labels and Dynamic Type pass, app icon, launch screen; XCUITest smoke; `ios/README.md`.
Verify: `curl -s "localhost:5000/api/export/csv?from=2026-09-01&to=2026-09-30&tz=America/Los_Angeles" -H "authorization: Bearer $TOKEN" | head -3`; simulator Profile → Practitioner Report → share sheet shows a multi-page PDF; Digest PDF button; Triggers → Evidence Ledger PDF.
Optional, needs a paid account: set `DEVELOPMENT_TEAM` and bundle id (suggest `app.tastetrace.ios`) in `project.yml`, `xcodebuild archive`, upload via Xcode Organizer; App Store Connect privacy labels (Health & Fitness data linked to identity; not HealthKit); a privacy policy URL on the landing site.

---

## Open questions (defaults in bold; change any of them)

1. Apple Developer account — **simulator-only until confirmed**; bundle id `app.tastetrace.ios`.
2. Web parity — **left as-is**; it keeps working because severity-only writes get a derived intensity and correlations keep their old columns.
3. AI — **Claude `claude-opus-5`, server-side, key optional**, rate-limited to one generation per user per 30 s (~600 output tokens per call).
4. Health data — symptom data is health-adjacent: App Store privacy labels, `PrivacyInfo.xcprivacy`, and a privacy-policy page are required before submission. No HealthKit.
5. "Clear Local Journal History" — **on-device cache wipe only**. Apple requires in-app account deletion for apps with accounts; a `DELETE /api/account` endpoint should be added before App Store submission.
6. Timezones — day bucketing becomes tz-aware; legacy rows keep their UTC `date` strings (**accept minor shifts on old days**, or backfill once).
7. Streak rule — **editable setting** (`streakMealsPerDay`, default 2).
8. Token expiry — **180-day sliding**; revoke all tokens on password change when that feature exists.
9. Barcode scanning, substitutes, restaurant suggestions — **out of scope** for M0–M6.
10. Repo hygiene — `assets/` and `PRODUCT.md` are untracked; commit them with the plan; add `*.xcodeproj`, `xcuserdata`, `.build` to `.gitignore` when `ios/` lands.
