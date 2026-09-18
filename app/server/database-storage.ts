import { and, eq, sql, gte, lte, desc, count, asc } from "drizzle-orm";
import { randomUUID } from "crypto";
import { db } from "./db";
import { IStorage } from "./storage";
import { 
  users, apiTokens, userSettings, meals, symptoms, customSymptoms, correlations, waitlistSignups,
  User, ProfilePatch, ApiToken, UserSettings, SettingsPatch,
  Meal, Symptom, CustomSymptom, Correlation,
  InsertUser, InsertMeal, UpdateMeal, InsertSymptom, UpdateSymptom, InsertCustomSymptom, InsertCorrelation,
  IngredientDetail, SymptomSeverity
} from "@shared/schema";
import { severityFromIntensity, intensityFromSeverity } from "@shared/severity";
import { customSymptomKey, catalogItemByName } from "@shared/symptomCatalog";
import { localDate } from "./analytics/time";

// Splits free-text notes into ingredient names (legacy web behaviour)
function ingredientsFromNotes(notes: string): string[] {
  return notes.split(/[\n,;]+/).map((line) => line.trim()).filter((line) => line.length > 0);
}

// Resolves the stored `severity` + `intensity` pair from whichever was given
function severityFields(severity?: string | null, intensity?: number | null) {
  if (intensity != null) {
    return { intensity, severity: severity || severityFromIntensity(intensity) };
  }
  const resolved = severity || SymptomSeverity.MODERATE;
  return { intensity: intensityFromSeverity(resolved), severity: resolved };
}

export class DatabaseStorage implements IStorage {
  // Waitlist operations
  async addWaitlistSignup(email: string): Promise<void> {
    // Signing up twice is not an error
    await db.insert(waitlistSignups).values({ email }).onConflictDoNothing();
  }

  // User operations
  async getUser(id: string): Promise<User | undefined> {
    const [user] = await db.select().from(users).where(eq(users.id, id));
    return user;
  }
  
  async getUserByEmail(email: string): Promise<User | undefined> {
    const [user] = await db.select().from(users).where(eq(users.email, email));
    return user;
  }

  async createUser(userData: InsertUser): Promise<User> {
    const userId = randomUUID();
    const userDataWithId = { ...userData, id: userId };
    const [user] = await db
      .insert(users)
      .values(userDataWithId)
      .returning();
    return user;
  }

  async updateUserProfile(userId: string, patch: ProfilePatch): Promise<User | undefined> {
    const [user] = await db.update(users)
      .set({ ...patch, updatedAt: new Date() })
      .where(eq(users.id, userId))
      .returning();
    return user;
  }

  async getFirstEntryAt(userId: string): Promise<Date | undefined> {
    const [meal] = await db.select({ t: meals.timestamp }).from(meals)
      .where(eq(meals.userId, userId)).orderBy(asc(meals.timestamp)).limit(1);
    const [symptom] = await db.select({ t: symptoms.timestamp }).from(symptoms)
      .where(eq(symptoms.userId, userId)).orderBy(asc(symptoms.timestamp)).limit(1);
    const candidates = [meal?.t, symptom?.t].filter((t): t is Date => !!t);
    if (candidates.length === 0) return undefined;
    return new Date(Math.min(...candidates.map((t) => t.getTime())));
  }

  // API token operations
  async createApiToken(token: { userId: string; tokenHash: string; deviceName: string | null; expiresAt: Date }): Promise<ApiToken> {
    const [created] = await db.insert(apiTokens).values(token).returning();
    return created;
  }

  async getApiTokenByHash(tokenHash: string): Promise<ApiToken | undefined> {
    const [token] = await db.select().from(apiTokens).where(eq(apiTokens.tokenHash, tokenHash));
    return token;
  }

  async touchApiToken(id: number, expiresAt: Date): Promise<void> {
    await db.update(apiTokens).set({ lastUsedAt: new Date(), expiresAt }).where(eq(apiTokens.id, id));
  }

  async listApiTokens(userId: string): Promise<ApiToken[]> {
    return await db.select().from(apiTokens)
      .where(and(eq(apiTokens.userId, userId), sql`${apiTokens.revokedAt} IS NULL`))
      .orderBy(desc(apiTokens.createdAt));
  }

  async revokeApiToken(id: number, userId: string): Promise<boolean> {
    const revoked = await db.update(apiTokens)
      .set({ revokedAt: new Date() })
      .where(and(eq(apiTokens.id, id), eq(apiTokens.userId, userId), sql`${apiTokens.revokedAt} IS NULL`))
      .returning({ id: apiTokens.id });
    return revoked.length > 0;
  }

  // Settings operations
  async getSettings(userId: string): Promise<UserSettings> {
    const [existing] = await db.select().from(userSettings).where(eq(userSettings.userId, userId));
    if (existing) return existing;
    const [created] = await db.insert(userSettings).values({ userId }).onConflictDoNothing().returning();
    if (created) return created;
    const [raced] = await db.select().from(userSettings).where(eq(userSettings.userId, userId));
    return raced;
  }

  async updateSettings(userId: string, patch: SettingsPatch): Promise<UserSettings> {
    await this.getSettings(userId);
    const [updated] = await db.update(userSettings)
      .set({ ...patch, updatedAt: new Date() })
      .where(eq(userSettings.userId, userId))
      .returning();
    return updated;
  }
  
  // Meal operations
  async getMeal(id: number, userId: string): Promise<Meal | undefined> {
    const [meal] = await db.select().from(meals).where(and(eq(meals.id, id), eq(meals.userId, userId)));
    return meal;
  }
  
  async getMealsByUser(userId: string): Promise<Meal[]> {
    return await db.select().from(meals).where(eq(meals.userId, userId));
  }
  
  async getMealsByUserAndTimeRange(userId: string, startTime: Date, endTime: Date): Promise<Meal[]> {
    const startIso = startTime.toISOString();
    const endIso = endTime.toISOString();
    
    return await db.select()
      .from(meals)
      .where(
        and(
          eq(meals.userId, userId),
          sql`${meals.timestamp} >= ${startIso} AND ${meals.timestamp} <= ${endIso}`
        )
      );
  }
  
  async createMeal(meal: InsertMeal, tz: string): Promise<Meal> {
    const timestamp = meal.timestamp ?? new Date();

    // Ingredient names come from the detailed list when present, else the
    // plain list, else (legacy web behaviour) from the notes text.
    let ingredients: string[] = [];
    let ingredientDetails: IngredientDetail[] | null = meal.ingredientDetails ?? null;
    if (ingredientDetails) {
      ingredients = ingredientDetails.map((i) => i.name);
    } else if (Array.isArray(meal.ingredients)) {
      ingredients = meal.ingredients;
    } else if (meal.notes) {
      ingredients = ingredientsFromNotes(meal.notes);
    }

    const [createdMeal] = await db.insert(meals)
      .values({ ...meal, timestamp, date: localDate(timestamp, tz), ingredients, ingredientDetails })
      .returning();
    return createdMeal;
  }
  
  async updateMeal(id: number, userId: string, mealUpdate: UpdateMeal, tz: string): Promise<Meal | undefined> {
    const updateData: Record<string, unknown> = { ...mealUpdate };
    if (mealUpdate.timestamp) {
      updateData.date = localDate(mealUpdate.timestamp, tz);
    }
    if (mealUpdate.ingredientDetails) {
      updateData.ingredients = mealUpdate.ingredientDetails.map((i) => i.name);
    }

    const [updatedMeal] = await db.update(meals)
      .set(updateData)
      .where(and(eq(meals.id, id), eq(meals.userId, userId)))
      .returning();
    return updatedMeal;
  }
  
  async deleteMeal(id: number, userId: string): Promise<boolean> {
    const deleted = await db.delete(meals)
      .where(and(eq(meals.id, id), eq(meals.userId, userId)))
      .returning({ id: meals.id });
    return deleted.length > 0;
  }
  
  // Symptom operations
  async getSymptom(id: number, userId: string): Promise<Symptom | undefined> {
    const [symptom] = await db.select().from(symptoms).where(and(eq(symptoms.id, id), eq(symptoms.userId, userId)));
    return symptom;
  }
  
  async getSymptomsByUser(userId: string): Promise<Symptom[]> {
    return await db.select().from(symptoms).where(eq(symptoms.userId, userId));
  }
  
  async getSymptomsByUserAndTimeRange(userId: string, startTime: Date, endTime: Date): Promise<Symptom[]> {
    const startIso = startTime.toISOString();
    const endIso = endTime.toISOString();
    
    return await db.select()
      .from(symptoms)
      .where(
        and(
          eq(symptoms.userId, userId),
          sql`${symptoms.timestamp} >= ${startIso} AND ${symptoms.timestamp} <= ${endIso}`
        )
      );
  }

  private symptomRow(symptom: InsertSymptom, tz: string) {
    const timestamp = symptom.timestamp ?? new Date();
    const catalogKey = symptom.catalogKey
      ?? catalogItemByName(symptom.name)?.key
      ?? customSymptomKey(symptom.name);
    return {
      ...symptom,
      ...severityFields(symptom.severity, symptom.intensity),
      catalogKey,
      timestamp,
      date: localDate(timestamp, tz),
    };
  }
  
  async createSymptom(symptom: InsertSymptom, tz: string): Promise<Symptom> {
    const [createdSymptom] = await db.insert(symptoms).values(this.symptomRow(symptom, tz)).returning();
    
    // Analyze correlations when a new symptom is added
    await this.analyzeCorrelations(createdSymptom);
    
    return createdSymptom;
  }

  async createSymptoms(list: InsertSymptom[], tz: string): Promise<Symptom[]> {
    if (list.length === 0) return [];
    const created = await db.insert(symptoms).values(list.map((s) => this.symptomRow(s, tz))).returning();
    for (const symptom of created) {
      await this.analyzeCorrelations(symptom);
    }
    return created;
  }
  
  async updateSymptom(id: number, userId: string, symptomUpdate: UpdateSymptom, tz: string): Promise<Symptom | undefined> {
    const updateData: Record<string, unknown> = { ...symptomUpdate };
    if (symptomUpdate.intensity != null || symptomUpdate.severity) {
      Object.assign(updateData, severityFields(symptomUpdate.severity, symptomUpdate.intensity));
    }
    if (symptomUpdate.timestamp) {
      updateData.date = localDate(symptomUpdate.timestamp, tz);
    }

    const [updatedSymptom] = await db.update(symptoms)
      .set(updateData)
      .where(and(eq(symptoms.id, id), eq(symptoms.userId, userId)))
      .returning();
    return updatedSymptom;
  }
  
  async deleteSymptom(id: number, userId: string): Promise<boolean> {
    const deleted = await db.delete(symptoms)
      .where(and(eq(symptoms.id, id), eq(symptoms.userId, userId)))
      .returning({ id: symptoms.id });
    return deleted.length > 0;
  }

  // Custom symptom catalog
  async getCustomSymptoms(userId: string): Promise<CustomSymptom[]> {
    return await db.select().from(customSymptoms)
      .where(eq(customSymptoms.userId, userId))
      .orderBy(asc(customSymptoms.name));
  }

  async createCustomSymptom(userId: string, symptom: InsertCustomSymptom): Promise<CustomSymptom> {
    const key = customSymptomKey(symptom.name);
    const [created] = await db.insert(customSymptoms)
      .values({ userId, key, name: symptom.name, emoji: symptom.emoji ?? "🩺", bodyRegion: symptom.bodyRegion ?? null })
      .onConflictDoUpdate({
        target: [customSymptoms.userId, customSymptoms.key],
        set: { name: symptom.name, emoji: symptom.emoji ?? "🩺", bodyRegion: symptom.bodyRegion ?? null },
      })
      .returning();
    return created;
  }

  async deleteCustomSymptom(id: number, userId: string): Promise<boolean> {
    const deleted = await db.delete(customSymptoms)
      .where(and(eq(customSymptoms.id, id), eq(customSymptoms.userId, userId)))
      .returning({ id: customSymptoms.id });
    return deleted.length > 0;
  }
  
  // Correlation operations
  async getCorrelation(id: number): Promise<Correlation | undefined> {
    const [correlation] = await db.select().from(correlations).where(eq(correlations.id, id));
    return correlation;
  }
  
  async getCorrelationsByUser(userId: string): Promise<Correlation[]> {
    // Only return correlations that have occurred multiple times (minimum threshold of 2)
    return await db.select()
      .from(correlations)
      .where(
        and(
          eq(correlations.userId, userId),
          gte(correlations.occurrences, 2) // Minimum 2 occurrences for correlation to be shown
        )
      );
  }
  
  async getCorrelationByFoodAndSymptom(userId: string, foodName: string, symptomName: string, isIngredient: boolean = false): Promise<Correlation | undefined> {
    const [correlation] = await db.select()
      .from(correlations)
      .where(
        and(
          eq(correlations.userId, userId),
          eq(correlations.foodName, foodName),
          eq(correlations.symptomName, symptomName),
          eq(correlations.isIngredient, isIngredient)
        )
      );
      
    return correlation;
  }
  
  async createOrUpdateCorrelation(correlation: InsertCorrelation): Promise<Correlation> {
    // Check if correlation already exists
    const existing = await this.getCorrelationByFoodAndSymptom(
      correlation.userId!, 
      correlation.foodName,
      correlation.symptomName,
      correlation.isIngredient || false
    );
    
    if (existing) {
      // Update existing correlation
      const [updated] = await db.update(correlations)
        .set({ 
          occurrences: existing.occurrences + 1,
          confidence: correlation.confidence || existing.confidence 
        })
        .where(eq(correlations.id, existing.id))
        .returning();
        
      return updated;
    } else {
      // Create new correlation
      const [newCorrelation] = await db.insert(correlations)
        .values(correlation)
        .returning();
        
      return newCorrelation;
    }
  }
  
  async updateCorrelationConfidence(id: number, confidence: number): Promise<Correlation | undefined> {
    const [updated] = await db.update(correlations)
      .set({ confidence })
      .where(eq(correlations.id, id))
      .returning();
      
    return updated;
  }
  
  async deleteCorrelation(id: number): Promise<boolean> {
    try {
      await db.delete(correlations).where(eq(correlations.id, id));
      return true;
    } catch (error) {
      console.error("Error deleting correlation:", error);
      return false;
    }
  }
  
  // Helper method to parse meal names into individual foods
  private parseMealIntoFoods(mealName: string): string[] {
    // Common separators that indicate multiple foods
    const separators = [',', '&', ' and ', ' with ', '+', '/'];
    
    // Single food combinations that should NOT be split (common compound foods)
    const compoundFoods = [
      'avocado toast', 'peanut butter', 'ice cream', 'fried rice', 'chicken sandwich',
      'tuna salad', 'caesar salad', 'grilled cheese', 'mac and cheese', 'fish and chips',
      'bread and butter', 'cookies and cream', 'salt and pepper', 'ham and cheese',
      'tomato soup', 'chicken soup', 'vegetable soup', 'apple pie', 'chocolate cake'
    ];
    
    // Check if this is a compound food that should stay together
    const lowerMealName = mealName.toLowerCase().trim();
    if (compoundFoods.some(compound => lowerMealName === compound)) {
      return [mealName.trim()];
    }
    
    // Check if meal name contains multiple foods (but not compound foods)
    const containsMultipleFoods = separators.some(sep => {
      const index = mealName.toLowerCase().indexOf(sep.toLowerCase());
      if (index === -1) return false;
      
      // Check if this separator is part of a compound food
      const beforeSep = mealName.substring(0, index + sep.length).toLowerCase();
      const afterSep = mealName.substring(index).toLowerCase();
      
      return !compoundFoods.some(compound => 
        beforeSep.includes(compound) || afterSep.includes(compound)
      );
    });
    
    if (!containsMultipleFoods) {
      return [mealName.trim()];
    }
    
    // Split by separators, being careful about compound foods
    let foods: string[] = [mealName];
    
    for (const separator of separators) {
      const temp: string[] = [];
      for (const food of foods) {
        // Only split if this separator isn't part of a compound food
        const lowerFood = food.toLowerCase();
        if (!compoundFoods.some(compound => lowerFood.includes(compound))) {
          const escapedSeparator = separator.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
          const parts = food.split(new RegExp(escapedSeparator, 'gi'));
          temp.push(...parts);
        } else {
          temp.push(food);
        }
      }
      foods = temp;
    }
    
    // Clean up and filter the results
    return foods
      .map(food => food.trim())
      .filter(food => food.length > 0)
      .map(food => {
        // Remove common prefixes/suffixes
        food = food.replace(/^(a |an |some |the )/i, '');
        food = food.replace(/\s*\(.*?\)\s*/g, ''); // Remove parentheses content
        return food.trim();
      })
      .filter(food => food.length > 2); // Remove very short items
  }

  // Helper methods
  private async analyzeCorrelations(symptom: Symptom): Promise<void> {
    const userId = symptom.userId;
    if (!userId) return;
    
    // Look for meals in the past 48 hours
    const now = new Date(symptom.timestamp);
    const twoDaysAgo = new Date(now);
    twoDaysAgo.setHours(twoDaysAgo.getHours() - 48);
    
    const recentMeals = await this.getMealsByUserAndTimeRange(userId, twoDaysAgo, now);
    
    // List of dietary tags to ignore for correlation generation
    const dietaryTags = ["gluten-free", "dairy-free", "grain-free", "sugar-free", 
                        "glutenfree", "dairyfree", "grainfree", "sugarfree"];
    
    // Update correlations for each meal
    for (const meal of recentMeals) {
      // Skip correlations with dietary restriction tags - don't create correlations for these
      const mealNameLower = meal.name.toLowerCase();
      if (dietaryTags.some(tag => mealNameLower.includes(tag))) {
        continue;
      }
      
      // Parse meal name into individual foods
      const individualFoods = this.parseMealIntoFoods(meal.name);
      
      // If it's a single food, create correlation as before
      if (individualFoods.length === 1) {
        await this.createOrUpdateCorrelation({
          userId,
          foodName: meal.name,
          symptomName: symptom.name,
          occurrences: 1,
          confidence: 50, // Initial confidence
          isIngredient: false
        });
      } else {
        // If multiple foods detected, create correlations for each individual food
        for (const food of individualFoods) {
          if (food.trim()) {
            const foodLower = food.toLowerCase();
            
            // Skip correlations for dietary tags
            if (dietaryTags.some(tag => foodLower.includes(tag))) {
              continue;
            }
            
            await this.createOrUpdateCorrelation({
              userId,
              foodName: food.trim(),
              symptomName: symptom.name,
              occurrences: 1,
              confidence: 50, // Same confidence as individual foods
              isIngredient: false
            });
          }
        }
      }
      
      // Also create correlations for explicit ingredients if available
      if (meal.ingredients && Array.isArray(meal.ingredients)) {
        for (const ingredient of meal.ingredients) {
          if (ingredient && ingredient.trim()) {
            const ingredientName = ingredient.trim();
            const ingredientLower = ingredientName.toLowerCase();
            
            // Skip correlations for dietary tags
            if (dietaryTags.some(tag => ingredientLower.includes(tag))) {
              continue;
            }
            
            await this.createOrUpdateCorrelation({
              userId,
              foodName: ingredientName,
              symptomName: symptom.name,
              occurrences: 1,
              confidence: 40, // Lower initial confidence for explicit ingredients
              isIngredient: true
            });
          }
        }
      }
    }
    
    // Update all correlation confidence scores
    await this.updateCorrelationConfidenceScores(userId);
  }

  // Method to regenerate all correlations for a user with improved parsing
  async regenerateCorrelations(userId: string): Promise<void> {
    // Delete all existing correlations for this user
    await db.delete(correlations).where(eq(correlations.userId, userId));
    
    // Get all symptoms for this user
    const userSymptoms = await this.getSymptomsByUser(userId);
    
    // Regenerate correlations for each symptom
    for (const symptom of userSymptoms) {
      await this.analyzeCorrelations(symptom);
    }
  }
  
  private async updateCorrelationConfidenceScores(userId: string): Promise<void> {
    // Get all correlations for this user
    const userCorrelations = await this.getCorrelationsByUser(userId);
    
    // Adjust confidence based on occurrence count
    for (const correlation of userCorrelations) {
      let adjustedConfidence = 50; // Base confidence
      
      // Increase confidence with more occurrences
      if (correlation.occurrences >= 5) {
        adjustedConfidence = 90; // High confidence
      } else if (correlation.occurrences >= 3) {
        adjustedConfidence = 75; // Moderate confidence
      } else if (correlation.occurrences === 2) {
        adjustedConfidence = 60; // Low-moderate confidence
      }
      
      // Lower confidence for ingredients slightly
      if (correlation.isIngredient) {
        adjustedConfidence = Math.max(adjustedConfidence - 10, 0);
      }
      
      // Update confidence if changed
      if (adjustedConfidence !== correlation.confidence) {
        await this.updateCorrelationConfidence(correlation.id, adjustedConfidence);
      }
    }
  }
}