import {
  InsertUser, User, ProfilePatch, ApiToken, UserSettings, SettingsPatch,
  InsertMeal, UpdateMeal, Meal, InsertSymptom, UpdateSymptom, Symptom, Dish, InsertDish,
  CustomSymptom, InsertCustomSymptom, Correlation, IngredientDetail, WatchlistItem,
} from "@shared/schema";
import { DatabaseStorage } from "./database-storage";

// Entry writes take the timezone the entry was logged in so `date` (the
// local calendar day) can be derived from `timestamp`.
export interface IStorage {
  // User operations
  getUser(id: string): Promise<User | undefined>;
  getUserByEmail(email: string): Promise<User | undefined>;
  createUser(user: InsertUser): Promise<User>;
  updateUserProfile(userId: string, patch: ProfilePatch): Promise<User | undefined>;
  getFirstEntryAt(userId: string): Promise<Date | undefined>;

  // API token operations
  createApiToken(token: { userId: string; tokenHash: string; deviceName: string | null; expiresAt: Date }): Promise<ApiToken>;
  getApiTokenByHash(tokenHash: string): Promise<ApiToken | undefined>;
  touchApiToken(id: number, expiresAt: Date): Promise<void>;
  listApiTokens(userId: string): Promise<ApiToken[]>;
  revokeApiToken(id: number, userId: string): Promise<boolean>;

  // Settings operations
  getSettings(userId: string): Promise<UserSettings>;
  updateSettings(userId: string, patch: SettingsPatch): Promise<UserSettings>;

  // Meal operations
  getMeal(id: number, userId: string): Promise<Meal | undefined>;
  getMealsByUser(userId: string): Promise<Meal[]>;
  getMealsByUserAndTimeRange(userId: string, startTime: Date, endTime: Date): Promise<Meal[]>;
  createMeal(meal: InsertMeal, tz: string): Promise<Meal>;
  updateMeal(id: number, userId: string, meal: UpdateMeal, tz: string): Promise<Meal | undefined>;
  deleteMeal(id: number, userId: string): Promise<boolean>;

  // Saved dish tiles
  getDishes(userId: string): Promise<Dish[]>;
  getDish(id: number, userId: string): Promise<Dish | undefined>;
  createDish(userId: string, dish: InsertDish): Promise<Dish>;
  updateDish(id: number, userId: string, dish: Partial<InsertDish>): Promise<Dish | undefined>;
  deleteDish(id: number, userId: string): Promise<boolean>;
  /** Logs a meal from a dish and bumps its usage counters. */
  logDish(dish: Dish, meal: { mealType: string; timestamp: Date; notes?: string | null; ingredientDetails?: IngredientDetail[] | null }, tz: string): Promise<Meal>;

  // Symptom operations
  getSymptom(id: number, userId: string): Promise<Symptom | undefined>;
  getSymptomsByUser(userId: string): Promise<Symptom[]>;
  getSymptomsByUserAndTimeRange(userId: string, startTime: Date, endTime: Date): Promise<Symptom[]>;
  createSymptom(symptom: InsertSymptom, tz: string): Promise<Symptom>;
  createSymptoms(symptoms: InsertSymptom[], tz: string): Promise<Symptom[]>;
  updateSymptom(id: number, userId: string, symptom: UpdateSymptom, tz: string): Promise<Symptom | undefined>;
  deleteSymptom(id: number, userId: string): Promise<boolean>;

  // Custom symptom catalog
  getCustomSymptoms(userId: string): Promise<CustomSymptom[]>;
  createCustomSymptom(userId: string, symptom: InsertCustomSymptom): Promise<CustomSymptom>;
  deleteCustomSymptom(id: number, userId: string): Promise<boolean>;

  // Correlation operations
  getCorrelation(id: number): Promise<Correlation | undefined>;
  /** Rows with at least two flare exposures (what the web app lists). */
  getCorrelationsByUser(userId: string): Promise<Correlation[]>;
  /** Every row, strongest first. */
  getAllCorrelationsByUser(userId: string): Promise<Correlation[]>;
  deleteCorrelation(id: number): Promise<boolean>;
  /** Recomputes all rows from the user's history. */
  regenerateCorrelations(userId: string): Promise<void>;

  // Watchlist (ingredients the user is monitoring)
  getWatchlist(userId: string): Promise<WatchlistItem[]>;
  addWatchlistItem(userId: string, ingredient: string, source: string): Promise<WatchlistItem>;
  removeWatchlistItem(id: number, userId: string): Promise<boolean>;

  // Waitlist operations
  addWaitlistSignup(email: string): Promise<void>;
}

// Use DatabaseStorage instead of MemStorage
export const storage = new DatabaseStorage();
