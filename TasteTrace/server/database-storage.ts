import { and, eq, sql, gte, lte, desc, count } from "drizzle-orm";
import { randomUUID } from "crypto";
import { db } from "./db";
import { IStorage } from "./storage";
import { 
  users, meals, symptoms, correlations,
  User, Meal, Symptom, Correlation,
  InsertUser, InsertMeal, InsertSymptom, InsertCorrelation,
  SymptomSeverity
} from "@shared/schema";

export class DatabaseStorage implements IStorage {
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
  
  // Meal operations
  async getMeal(id: number): Promise<Meal | undefined> {
    const [meal] = await db.select().from(meals).where(eq(meals.id, id));
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
  
  async createMeal(meal: InsertMeal): Promise<Meal> {
    try {
      // Set today's date for the meal
      const today = new Date().toISOString().split('T')[0];
      const mealWithDate = { ...meal, date: today };
      
      // Make sure we have a proper timestamp value
      if (!mealWithDate.timestamp) {
        mealWithDate.timestamp = new Date();
      } else if (typeof mealWithDate.timestamp === 'string') {
        try {
          mealWithDate.timestamp = new Date(mealWithDate.timestamp);
        } catch (e) {
          console.error("Invalid timestamp format:", e);
          mealWithDate.timestamp = new Date();
        }
      }
      
      // Extract ingredients from notes if provided
      let ingredients: string[] = [];
      if (mealWithDate.ingredients && Array.isArray(mealWithDate.ingredients)) {
        ingredients = mealWithDate.ingredients;
      } else if (meal.notes) {
        // Try to extract ingredients from notes
        const noteLines = meal.notes.split(/[\n,;]+/);
        if (noteLines.length > 0) {
          ingredients = noteLines.map(line => line.trim()).filter(line => line.length > 0);
        }
      }
      
      const [createdMeal] = await db.insert(meals)
        .values({ ...mealWithDate, ingredients })
        .returning();
        
      return createdMeal;
    } catch (error) {
      console.error("Error creating meal:", error);
      throw error;
    }
  }
  
  async updateMeal(id: number, mealUpdate: Partial<InsertMeal>): Promise<Meal | undefined> {
    try {
      // Extract ingredients from notes if provided
      const updateData: any = { ...mealUpdate };
      
      // Make sure we have a proper timestamp value
      if (updateData.timestamp) {
        if (typeof updateData.timestamp === 'string') {
          try {
            updateData.timestamp = new Date(updateData.timestamp);
          } catch (e) {
            console.error("Invalid timestamp format:", e);
            // Don't override the existing timestamp if there's an error
            delete updateData.timestamp;
          }
        }
      }
      
      if (mealUpdate.notes) {
        // Try to extract ingredients from notes
        const noteLines = mealUpdate.notes.split(/[\n,;]+/);
        if (noteLines.length > 0) {
          updateData.ingredients = noteLines
            .map(line => line.trim())
            .filter(line => line.length > 0);
        }
      }
      
      const [updatedMeal] = await db.update(meals)
        .set(updateData)
        .where(eq(meals.id, id))
        .returning();
        
      return updatedMeal;
    } catch (error) {
      console.error("Error updating meal:", error);
      throw error;
    }
  }
  
  async deleteMeal(id: number): Promise<boolean> {
    try {
      // First check if the meal exists
      const meal = await this.getMeal(id);
      if (!meal) {
        return false;
      }
      
      // If meal exists, delete it
      await db.delete(meals).where(eq(meals.id, id));
      return true;
    } catch (error) {
      console.error("Error deleting meal:", error);
      return false;
    }
  }
  
  // Symptom operations
  async getSymptom(id: number): Promise<Symptom | undefined> {
    const [symptom] = await db.select().from(symptoms).where(eq(symptoms.id, id));
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
  
  async createSymptom(symptom: InsertSymptom): Promise<Symptom> {
    // Set today's date for the symptom
    const today = new Date().toISOString().split('T')[0];
    const symptomWithDate = { ...symptom, date: today };
    
    const [createdSymptom] = await db.insert(symptoms).values(symptomWithDate).returning();
    
    // Analyze correlations when a new symptom is added
    await this.analyzeCorrelations(createdSymptom);
    
    return createdSymptom;
  }
  
  async updateSymptom(id: number, symptomUpdate: Partial<InsertSymptom>): Promise<Symptom | undefined> {
    const [updatedSymptom] = await db.update(symptoms)
      .set(symptomUpdate)
      .where(eq(symptoms.id, id))
      .returning();
      
    return updatedSymptom;
  }
  
  async deleteSymptom(id: number): Promise<boolean> {
    try {
      await db.delete(symptoms).where(eq(symptoms.id, id));
      return true;
    } catch (error) {
      console.error("Error deleting symptom:", error);
      return false;
    }
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