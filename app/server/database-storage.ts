import { and, eq, sql, gte, lte, desc, count, asc } from "drizzle-orm";
import { randomUUID } from "crypto";
import { db } from "./db";
import { IStorage } from "./storage";
import { 
  users, apiTokens, userSettings, meals, symptoms, customSymptoms, correlations, waitlistSignups, dishes, watchlist,
  User, ProfilePatch, ApiToken, UserSettings, SettingsPatch,
  Meal, Symptom, CustomSymptom, Correlation, Dish, WatchlistItem,
  InsertUser, InsertMeal, UpdateMeal, InsertSymptom, UpdateSymptom, InsertCustomSymptom, InsertDish,
  IngredientDetail, SymptomSeverity
} from "@shared/schema";
import { severityFromIntensity, intensityFromSeverity } from "@shared/severity";
import { customSymptomKey, catalogItemByName } from "@shared/symptomCatalog";
import { localDate } from "./analytics/time";
import { computeCorrelations } from "./analytics/correlations";

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
  
  // Saved dish tiles
  async getDishes(userId: string): Promise<Dish[]> {
    return await db.select().from(dishes)
      .where(eq(dishes.userId, userId))
      .orderBy(sql`${dishes.lastLoggedAt} DESC NULLS LAST`, desc(dishes.timesLogged), asc(dishes.name));
  }

  async getDish(id: number, userId: string): Promise<Dish | undefined> {
    const [dish] = await db.select().from(dishes).where(and(eq(dishes.id, id), eq(dishes.userId, userId)));
    return dish;
  }

  async createDish(userId: string, dish: InsertDish): Promise<Dish> {
    const [created] = await db.insert(dishes).values({ ...dish, userId }).returning();
    return created;
  }

  async updateDish(id: number, userId: string, dish: Partial<InsertDish>): Promise<Dish | undefined> {
    const [updated] = await db.update(dishes)
      .set({ ...dish, updatedAt: new Date() })
      .where(and(eq(dishes.id, id), eq(dishes.userId, userId)))
      .returning();
    return updated;
  }

  async deleteDish(id: number, userId: string): Promise<boolean> {
    const deleted = await db.delete(dishes)
      .where(and(eq(dishes.id, id), eq(dishes.userId, userId)))
      .returning({ id: dishes.id });
    return deleted.length > 0;
  }

  async logDish(dish: Dish, meal: { mealType: string; timestamp: Date; notes?: string | null; ingredientDetails?: IngredientDetail[] | null }, tz: string): Promise<Meal> {
    const created = await this.createMeal({
      userId: dish.userId,
      name: dish.name,
      mealType: meal.mealType,
      timestamp: meal.timestamp,
      notes: meal.notes ?? null,
      isCustom: true,
      ingredientDetails: meal.ingredientDetails ?? dish.ingredients,
      dishId: dish.id,
      containsGluten: dish.containsGluten,
      containsDairy: dish.containsDairy,
      containsGrains: dish.containsGrains,
      containsSugar: dish.containsSugar,
      containsNuts: dish.containsNuts,
    }, tz);
    await db.update(dishes)
      .set({ timesLogged: sql`${dishes.timesLogged} + 1`, lastLoggedAt: meal.timestamp })
      .where(eq(dishes.id, dish.id));
    return created;
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
    
    // Keep correlations current so the web app's next fetch already sees them
    await this.regenerateCorrelations(createdSymptom.userId!);
    
    return createdSymptom;
  }

  async createSymptoms(list: InsertSymptom[], tz: string): Promise<Symptom[]> {
    if (list.length === 0) return [];
    const created = await db.insert(symptoms).values(list.map((s) => this.symptomRow(s, tz))).returning();
    await this.regenerateCorrelations(created[0].userId!);
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
  
  // Watchlist
  async getWatchlist(userId: string): Promise<WatchlistItem[]> {
    return await db.select().from(watchlist).where(eq(watchlist.userId, userId)).orderBy(desc(watchlist.createdAt));
  }

  async addWatchlistItem(userId: string, ingredient: string, source: string): Promise<WatchlistItem> {
    const normalized = ingredient.trim().toLowerCase().replace(/\s+/g, " ");
    const [item] = await db.insert(watchlist)
      .values({ userId, ingredient: normalized, source })
      .onConflictDoUpdate({ target: [watchlist.userId, watchlist.ingredient], set: { source } })
      .returning();
    return item;
  }

  async removeWatchlistItem(id: number, userId: string): Promise<boolean> {
    const deleted = await db.delete(watchlist)
      .where(and(eq(watchlist.id, id), eq(watchlist.userId, userId)))
      .returning({ id: watchlist.id });
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

  async getAllCorrelationsByUser(userId: string): Promise<Correlation[]> {
    return await db.select().from(correlations)
      .where(eq(correlations.userId, userId))
      .orderBy(desc(correlations.confidence), desc(correlations.flareExposures));
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

  /**
   * Recomputes every correlation for a user from their full history with
   * the v2 engine (server/analytics/correlations.ts) and replaces the rows.
   */
  async regenerateCorrelations(userId: string): Promise<void> {
    const [userMeals, userSymptoms, settings] = await Promise.all([
      this.getMealsByUser(userId),
      this.getSymptomsByUser(userId),
      this.getSettings(userId),
    ]);
    const rows = computeCorrelations(userMeals, userSymptoms, settings);

    await db.transaction(async (tx) => {
      await tx.delete(correlations).where(eq(correlations.userId, userId));
      for (let i = 0; i < rows.length; i += 200) {
        await tx.insert(correlations).values(rows.slice(i, i + 200).map((row) => ({ ...row, userId, updatedAt: new Date() })));
      }
    });
  }
}
