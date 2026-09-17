import { InsertUser, User, InsertMeal, Meal, InsertSymptom, Symptom, InsertCorrelation, Correlation } from "@shared/schema";
import { DatabaseStorage } from "./database-storage";

export interface IStorage {
  // User operations
  getUser(id: string): Promise<User | undefined>;
  getUserByEmail(email: string): Promise<User | undefined>;
  createUser(user: InsertUser): Promise<User>;
  
  // Meal operations
  getMeal(id: number): Promise<Meal | undefined>;
  getMealsByUser(userId: string): Promise<Meal[]>;
  getMealsByUserAndTimeRange(userId: string, startTime: Date, endTime: Date): Promise<Meal[]>;
  createMeal(meal: InsertMeal): Promise<Meal>;
  updateMeal(id: number, meal: Partial<InsertMeal>): Promise<Meal | undefined>;
  deleteMeal(id: number): Promise<boolean>;
  
  // Symptom operations
  getSymptom(id: number): Promise<Symptom | undefined>;
  getSymptomsByUser(userId: string): Promise<Symptom[]>;
  getSymptomsByUserAndTimeRange(userId: string, startTime: Date, endTime: Date): Promise<Symptom[]>;
  createSymptom(symptom: InsertSymptom): Promise<Symptom>;
  updateSymptom(id: number, symptom: Partial<InsertSymptom>): Promise<Symptom | undefined>;
  deleteSymptom(id: number): Promise<boolean>;
  
  // Correlation operations
  getCorrelation(id: number): Promise<Correlation | undefined>;
  getCorrelationsByUser(userId: string): Promise<Correlation[]>;
  getCorrelationByFoodAndSymptom(userId: string, foodName: string, symptomName: string, isIngredient?: boolean): Promise<Correlation | undefined>;
  createOrUpdateCorrelation(correlation: InsertCorrelation): Promise<Correlation>;
  updateCorrelationConfidence(id: number, confidence: number): Promise<Correlation | undefined>;
  deleteCorrelation(id: number): Promise<boolean>;
  regenerateCorrelations(userId: string): Promise<void>;
}

// Use DatabaseStorage instead of MemStorage
export const storage = new DatabaseStorage();