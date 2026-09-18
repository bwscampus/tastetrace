import { pgTable, text, serial, integer, boolean, timestamp, varchar, json, real, index, uniqueIndex } from "drizzle-orm/pg-core";
import { sql } from "drizzle-orm";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod";

// Local calendar day (YYYY-MM-DD). The app fills this from the entry's
// timestamp in the user's timezone; the DB default only covers raw inserts.
const localDateDefault = sql`to_char(now(), 'YYYY-MM-DD')`;

// Session storage table.
export const sessions = pgTable(
  "sessions",
  {
    sid: varchar("sid").primaryKey(),
    sess: json("sess").notNull(),
    expire: timestamp("expire").notNull(),
  },
  (table) => [index("IDX_session_expire").on(table.expire)],
);

// User storage table
export const users = pgTable("users", {
  id: varchar("id").primaryKey().notNull(),
  email: varchar("email").unique().notNull(),
  password: varchar("password").notNull(),
  firstName: varchar("first_name"),
  lastName: varchar("last_name"),
  displayName: varchar("display_name"),
  avatarEmoji: varchar("avatar_emoji"),
  discoveryPurpose: text("discovery_purpose"),
  sensitivityTags: json("sensitivity_tags").$type<string[]>().default([]),
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
});

// Bearer tokens for the mobile app (one per device). Only the sha256 of the
// token is stored.
export const apiTokens = pgTable(
  "api_tokens",
  {
    id: serial("id").primaryKey(),
    userId: varchar("user_id").notNull().references(() => users.id),
    tokenHash: varchar("token_hash", { length: 64 }).notNull().unique(),
    deviceName: text("device_name"),
    createdAt: timestamp("created_at").defaultNow().notNull(),
    lastUsedAt: timestamp("last_used_at"),
    expiresAt: timestamp("expires_at"),
    revokedAt: timestamp("revoked_at"),
  },
  (t) => [index("IDX_api_tokens_user").on(t.userId)],
);

// Per-user preferences that drive analytics and reminders
export const userSettings = pgTable("user_settings", {
  userId: varchar("user_id").primaryKey().references(() => users.id),
  timezone: text("timezone").notNull().default("UTC"), // IANA name
  correlationWindowHours: integer("correlation_window_hours").notNull().default(24),
  minTriggerCount: integer("min_trigger_count").notNull().default(2),
  minConfidence: integer("min_confidence").notNull().default(50),
  streakMealsPerDay: integer("streak_meals_per_day").notNull().default(2),
  nudgeTime: text("nudge_time").notNull().default("20:30"), // local HH:mm
  nudgesEnabled: boolean("nudges_enabled").notNull().default(true),
  mealCheckInsEnabled: boolean("meal_check_ins_enabled").notNull().default(false),
  updatedAt: timestamp("updated_at").defaultNow(),
});

export type IngredientDetail = { name: string; cookMethod?: string | null };

// Saved dish tiles ("shortcuts") for one-tap meal logging
export const dishes = pgTable("dishes", {
  id: serial("id").primaryKey(),
  userId: varchar("user_id").notNull().references(() => users.id),
  name: text("name").notNull(),
  emoji: varchar("emoji").notNull().default("🍽️"),
  ingredients: json("ingredients").$type<IngredientDetail[]>().notNull().default([]),
  containsGluten: boolean("contains_gluten").default(false),
  containsDairy: boolean("contains_dairy").default(false),
  containsGrains: boolean("contains_grains").default(false),
  containsSugar: boolean("contains_sugar").default(false),
  containsNuts: boolean("contains_nuts").default(false),
  timesLogged: integer("times_logged").notNull().default(0),
  lastLoggedAt: timestamp("last_logged_at"),
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
});

export const meals = pgTable("meals", {
  id: serial("id").primaryKey(),
  userId: varchar("user_id").references(() => users.id),
  name: text("name").notNull(),
  mealType: text("meal_type").notNull(), // Breakfast, Lunch, Dinner, Snack
  timestamp: timestamp("timestamp").notNull().defaultNow(),
  notes: text("notes"),
  isCustom: boolean("is_custom").default(false),
  ingredients: json("ingredients").$type<string[]>().default([]),
  // Ingredients with cook methods (mobile); `ingredients` mirrors the names
  ingredientDetails: json("ingredient_details").$type<IngredientDetail[]>(),
  dishId: integer("dish_id").references(() => dishes.id, { onDelete: "set null" }),
  containsGluten: boolean("contains_gluten").default(false),
  containsDairy: boolean("contains_dairy").default(false), 
  containsGrains: boolean("contains_grains").default(false),
  containsSugar: boolean("contains_sugar").default(false),
  containsNuts: boolean("contains_nuts").default(false),
  date: text("date").notNull().default(localDateDefault),
});

export const symptoms = pgTable("symptoms", {
  id: serial("id").primaryKey(),
  userId: varchar("user_id").references(() => users.id),
  name: text("name").notNull(),
  severity: text("severity").notNull(), // Mild, Moderate, Severe
  intensity: integer("intensity"), // 1-5; always stored alongside severity
  durationMinutes: integer("duration_minutes"),
  catalogKey: text("catalog_key"), // see shared/symptomCatalog.ts
  timestamp: timestamp("timestamp").notNull().defaultNow(),
  notes: text("notes"),
  date: text("date").notNull().default(localDateDefault),
});

// User-defined symptoms beyond the default catalog
export const customSymptoms = pgTable(
  "custom_symptoms",
  {
    id: serial("id").primaryKey(),
    userId: varchar("user_id").notNull().references(() => users.id),
    key: text("key").notNull(),
    name: text("name").notNull(),
    emoji: varchar("emoji").notNull().default("🩺"),
    bodyRegion: text("body_region"),
    createdAt: timestamp("created_at").defaultNow(),
  },
  (t) => [uniqueIndex("UQ_custom_symptoms").on(t.userId, t.key)],
);

export const correlations = pgTable("correlations", {
  id: serial("id").primaryKey(),
  userId: varchar("user_id").references(() => users.id),
  foodName: text("food_name").notNull(),
  symptomName: text("symptom_name").notNull(),
  occurrences: integer("occurrences").notNull().default(1),
  confidence: integer("confidence").notNull().default(0), // 0-100
  isIngredient: boolean("is_ingredient").default(false),
  // v2 engine fields (see server/analytics); legacy columns above keep working
  dimension: text("dimension").notNull().default("food"), // food | ingredient | cook_method
  exposures: integer("exposures").notNull().default(0),
  flareExposures: integer("flare_exposures").notNull().default(0),
  baselineRate: real("baseline_rate"),
  lift: real("lift"),
  avgOnsetHours: real("avg_onset_hours"),
  windowHours: integer("window_hours"),
  lastFlareAt: timestamp("last_flare_at"),
  updatedAt: timestamp("updated_at").defaultNow(),
});

// Ingredients the user is keeping an eye on
export const watchlist = pgTable(
  "watchlist",
  {
    id: serial("id").primaryKey(),
    userId: varchar("user_id").notNull().references(() => users.id),
    ingredient: text("ingredient").notNull(), // normalized lowercase
    source: text("source").notNull().default("manual"), // manual | suspect | synthesis
    createdAt: timestamp("created_at").defaultNow(),
  },
  (t) => [uniqueIndex("UQ_watchlist").on(t.userId, t.ingredient)],
);

// Cached AI pattern summaries, keyed by the data they were generated from
export const aiSyntheses = pgTable(
  "ai_syntheses",
  {
    id: serial("id").primaryKey(),
    userId: varchar("user_id").notNull().references(() => users.id),
    kind: text("kind").notNull(), // "suspects_weekly"
    weekStart: text("week_start").notNull(),
    symptomFilter: text("symptom_filter").notNull().default(""),
    inputHash: varchar("input_hash", { length: 64 }).notNull(),
    source: text("source").notNull(), // "claude" | "rules"
    model: text("model"),
    text: text("text").notNull(),
    createdAt: timestamp("created_at").defaultNow(),
  },
  (t) => [uniqueIndex("UQ_ai_synth").on(t.userId, t.kind, t.weekStart, t.symptomFilter)],
);

// Signups from the landing page (tastetrace.app)
export const waitlistSignups = pgTable("waitlist_signups", {
  id: serial("id").primaryKey(),
  email: varchar("email").unique().notNull(),
  createdAt: timestamp("created_at").defaultNow(),
});

// Schemas
export const ingredientDetailSchema = z.object({
  name: z.string().trim().min(1).max(100),
  cookMethod: z.string().trim().max(40).nullable().optional(),
});

export const insertUserSchema = createInsertSchema(users).pick({
  email: true,
  password: true,
  firstName: true,
  lastName: true,
});

export const loginUserSchema = createInsertSchema(users).pick({
  email: true,
  password: true,
});

export const insertMealSchema = createInsertSchema(meals).pick({
  userId: true,
  name: true,
  mealType: true,
  notes: true,
  isCustom: true,
  ingredients: true,
  containsGluten: true,
  containsDairy: true,
  containsGrains: true,
  containsSugar: true,
  containsNuts: true,
  timestamp: true,
  date: true,
}).extend({
  ingredients: z.array(z.string()).optional().nullable(),
  ingredientDetails: z.array(ingredientDetailSchema).optional().nullable(),
  dishId: z.number().int().optional().nullable(),
});

export const updateMealSchema = insertMealSchema.omit({ userId: true }).partial();

export const insertSymptomSchema = createInsertSchema(symptoms).pick({
  userId: true,
  name: true,
  severity: true,
  notes: true,
  timestamp: true,
  date: true,
}).extend({
  // The web sends `severity`; the mobile app sends `intensity`. The storage
  // layer fills in whichever is missing.
  severity: z.string().optional(),
  intensity: z.number().int().min(1).max(5).optional().nullable(),
  durationMinutes: z.number().int().min(0).max(60 * 24 * 7).optional().nullable(),
  catalogKey: z.string().max(80).optional().nullable(),
}).refine((s) => s.severity || s.intensity, {
  message: "Either severity or intensity is required",
  path: ["intensity"],
});

export const updateSymptomSchema = z.object({
  name: z.string().min(1).optional(),
  severity: z.string().optional(),
  intensity: z.number().int().min(1).max(5).optional().nullable(),
  durationMinutes: z.number().int().min(0).max(60 * 24 * 7).optional().nullable(),
  catalogKey: z.string().max(80).optional().nullable(),
  timestamp: z.date().optional(),
  notes: z.string().optional().nullable(),
});

export const insertDishSchema = createInsertSchema(dishes).pick({
  name: true,
  emoji: true,
  containsGluten: true,
  containsDairy: true,
  containsGrains: true,
  containsSugar: true,
  containsNuts: true,
}).extend({
  ingredients: z.array(ingredientDetailSchema).default([]),
});

export const insertCustomSymptomSchema = z.object({
  name: z.string().trim().min(1).max(60),
  emoji: z.string().trim().min(1).max(8).optional(),
  bodyRegion: z.string().trim().max(60).optional().nullable(),
});

export const settingsPatchSchema = z.object({
  timezone: z.string().min(1).max(64).optional(),
  correlationWindowHours: z.number().int().min(1).max(72).optional(),
  minTriggerCount: z.number().int().min(1).max(20).optional(),
  minConfidence: z.number().int().min(0).max(100).optional(),
  streakMealsPerDay: z.number().int().min(1).max(6).optional(),
  nudgeTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/).optional(),
  nudgesEnabled: z.boolean().optional(),
  mealCheckInsEnabled: z.boolean().optional(),
});

export const profilePatchSchema = z.object({
  firstName: z.string().trim().max(60).optional().nullable(),
  lastName: z.string().trim().max(60).optional().nullable(),
  displayName: z.string().trim().max(80).optional().nullable(),
  avatarEmoji: z.string().trim().max(8).optional().nullable(),
  discoveryPurpose: z.string().trim().max(200).optional().nullable(),
  sensitivityTags: z.array(z.string().trim().min(1).max(40)).max(20).optional(),
});

export const insertCorrelationSchema = createInsertSchema(correlations).pick({
  userId: true,
  foodName: true,
  symptomName: true,
  occurrences: true,
  confidence: true,
  isIngredient: true,
});

// Types
export type InsertUser = z.infer<typeof insertUserSchema>;
export type LoginUser = z.infer<typeof loginUserSchema>;
export type User = typeof users.$inferSelect;
export type ApiToken = typeof apiTokens.$inferSelect;
export type UserSettings = typeof userSettings.$inferSelect;
export type SettingsPatch = z.infer<typeof settingsPatchSchema>;
export type ProfilePatch = z.infer<typeof profilePatchSchema>;
export type Dish = typeof dishes.$inferSelect;
export type InsertDish = z.infer<typeof insertDishSchema>;
export type Meal = typeof meals.$inferSelect;
export type InsertMeal = z.infer<typeof insertMealSchema>;
export type UpdateMeal = z.infer<typeof updateMealSchema>;
export type Symptom = typeof symptoms.$inferSelect;
export type InsertSymptom = z.infer<typeof insertSymptomSchema>;
export type UpdateSymptom = z.infer<typeof updateSymptomSchema>;
export type CustomSymptom = typeof customSymptoms.$inferSelect;
export type InsertCustomSymptom = z.infer<typeof insertCustomSymptomSchema>;
export type Correlation = typeof correlations.$inferSelect;
export type InsertCorrelation = z.infer<typeof insertCorrelationSchema>;
export type WatchlistItem = typeof watchlist.$inferSelect;
export type AiSynthesis = typeof aiSyntheses.$inferSelect;

// Enums
export enum MealType {
  BREAKFAST = "Breakfast",
  LUNCH = "Lunch",
  DINNER = "Dinner",
  SNACK = "Snack"
}

export enum SymptomSeverity {
  MILD = "Mild",
  MODERATE = "Moderate",
  SEVERE = "Severe"
}
