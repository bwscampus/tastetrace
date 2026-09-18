import {
  InsertUser, User, ProfilePatch, ApiToken, UserSettings, SettingsPatch,
  InsertMeal, UpdateMeal, Meal, InsertSymptom, UpdateSymptom, Symptom,
  CustomSymptom, InsertCustomSymptom, InsertCorrelation, Correlation,
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
  getCorrelationsByUser(userId: string): Promise<Correlation[]>;
  getCorrelationByFoodAndSymptom(userId: string, foodName: string, symptomName: string, isIngredient?: boolean): Promise<Correlation | undefined>;
  createOrUpdateCorrelation(correlation: InsertCorrelation): Promise<Correlation>;
  updateCorrelationConfidence(id: number, confidence: number): Promise<Correlation | undefined>;
  deleteCorrelation(id: number): Promise<boolean>;
  regenerateCorrelations(userId: string): Promise<void>;

  // Waitlist operations
  addWaitlistSignup(email: string): Promise<void>;
}

// Use DatabaseStorage instead of MemStorage
export const storage = new DatabaseStorage();
