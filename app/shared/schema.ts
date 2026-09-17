import { pgTable, text, serial, integer, boolean, timestamp, varchar, json, index } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod";

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
  containsGluten: boolean("contains_gluten").default(false),
  containsDairy: boolean("contains_dairy").default(false), 
  containsGrains: boolean("contains_grains").default(false),
  containsSugar: boolean("contains_sugar").default(false),
  containsNuts: boolean("contains_nuts").default(false),
  date: text("date").notNull().default(new Date().toISOString().split('T')[0]),
});

export const symptoms = pgTable("symptoms", {
  id: serial("id").primaryKey(),
  userId: varchar("user_id").references(() => users.id),
  name: text("name").notNull(),
  severity: text("severity").notNull(), // Mild, Moderate, Severe
  timestamp: timestamp("timestamp").notNull().defaultNow(),
  notes: text("notes"),
  date: text("date").notNull().default(new Date().toISOString().split('T')[0]),
});

export const correlations = pgTable("correlations", {
  id: serial("id").primaryKey(),
  userId: varchar("user_id").references(() => users.id),
  foodName: text("food_name").notNull(),
  symptomName: text("symptom_name").notNull(),
  occurrences: integer("occurrences").notNull().default(1),
  confidence: integer("confidence").notNull().default(0), // 0-100
  isIngredient: boolean("is_ingredient").default(false),
});

// Signups from the landing page (tastetrace.app)
export const waitlistSignups = pgTable("waitlist_signups", {
  id: serial("id").primaryKey(),
  email: varchar("email").unique().notNull(),
  createdAt: timestamp("created_at").defaultNow(),
});

// Schemas
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
});

export const insertSymptomSchema = createInsertSchema(symptoms).pick({
  userId: true,
  name: true,
  severity: true,
  notes: true,
  date: true,
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
export type Meal = typeof meals.$inferSelect;
export type InsertMeal = z.infer<typeof insertMealSchema>;
export type Symptom = typeof symptoms.$inferSelect;
export type InsertSymptom = z.infer<typeof insertSymptomSchema>;
export type Correlation = typeof correlations.$inferSelect;
export type InsertCorrelation = z.infer<typeof insertCorrelationSchema>;

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
