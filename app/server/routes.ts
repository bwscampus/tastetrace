import type { Express, Request, Response } from "express";
import { storage } from "./storage";
import { setupAuth, isAuthenticated } from "./auth";
import { 
  insertMealSchema, 
  insertSymptomSchema,
  MealType, 
  SymptomSeverity,
  Meal,
  Symptom 
} from "@shared/schema";
import { z } from "zod";
import { startOfDay, endOfDay, parse } from "date-fns";

function formatDateForQuery(date: Date | string): Date {
  const d = typeof date === 'string' ? new Date(date) : date;
  return d;
}

// Origins allowed to post to the waitlist endpoint (the landing site)
const WAITLIST_ORIGINS = (process.env.WAITLIST_ORIGINS ||
  "https://tastetrace.up.railway.app,https://tastetrace.app,https://www.tastetrace.app")
  .split(",")
  .map((origin) => origin.trim());

const waitlistSchema = z.object({
  email: z.string().trim().toLowerCase().email().max(254),
  company: z.string().optional(), // honeypot, left empty by real visitors
});

export function registerRoutes(app: Express): void {
  // Waitlist signups come cross-origin from the landing page, so this is
  // registered before the session middleware and answers CORS itself.
  app.use("/api/waitlist", (req: Request, res: Response, next) => {
    const origin = req.headers.origin;
    if (origin && WAITLIST_ORIGINS.includes(origin)) {
      res.setHeader("Access-Control-Allow-Origin", origin);
      res.setHeader("Vary", "Origin");
      res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
      res.setHeader("Access-Control-Allow-Headers", "Content-Type");
    }
    if (req.method === "OPTIONS") return res.sendStatus(204);
    next();
  });

  app.post("/api/waitlist", async (req: Request, res: Response) => {
    const parsed = waitlistSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ message: "Enter a valid email address" });
    }

    try {
      if (!parsed.data.company) {
        await storage.addWaitlistSignup(parsed.data.email);
      }
      res.status(201).json({ message: "You're on the list" });
    } catch (error) {
      console.error("Error adding waitlist signup:", error);
      res.status(500).json({ message: "Could not join the waitlist" });
    }
  });

  // Setup authentication
  setupAuth(app);

  // Forgot password endpoint
  app.post('/api/forgot-password', async (req: Request, res: Response) => {
    try {
      const { email } = req.body;
      
      if (!email) {
        return res.status(400).json({ message: "Email is required" });
      }

      // Check if user exists
      const user = await storage.getUserByEmail(email);
      if (!user) {
        // Don't reveal if user exists or not for security
        return res.status(200).json({ message: "If an account with that email exists, a password reset link has been sent." });
      }

      // In a real application, you would:
      // 1. Generate a secure reset token
      // 2. Store it in the database with an expiration time
      // 3. Send an email with the reset link
      // 
      // For this demo, we'll just return a success message
      console.log(`Password reset requested for: ${email}`);
      
      res.status(200).json({ 
        message: "If an account with that email exists, a password reset link has been sent." 
      });
    } catch (error) {
      console.error("Error processing forgot password:", error);
      res.status(500).json({ message: "Internal server error" });
    }
  });

  // Meals API
  app.get("/api/meals", isAuthenticated, async (req: any, res: Response) => {
    const userId = req.user.id;
    
    try {
      const meals = await storage.getMealsByUser(userId);
      res.json(meals);
    } catch (error) {
      console.error("Error getting meals:", error);
      res.status(500).json({ message: "Failed to get meals" });
    }
  });

  app.post("/api/meals", isAuthenticated, async (req: any, res: Response) => {
    const userId = req.user.id;
    
    try {
      // Prepare the meal data, handling timestamp properly
      const mealData = { ...req.body, userId };
      
      // If timestamp is a string, convert it to a Date object before validation
      if (mealData.timestamp && typeof mealData.timestamp === 'string') {
        try {
          mealData.timestamp = new Date(mealData.timestamp);
        } catch (e) {
          return res.status(400).json({ message: "Invalid timestamp format" });
        }
      }
      
      const validatedData = insertMealSchema.parse(mealData);
      const meal = await storage.createMeal(validatedData);
      res.status(201).json(meal);
    } catch (error) {
      if (error instanceof z.ZodError) {
        res.status(400).json({ message: "Invalid meal data", errors: error.errors });
      } else {
        console.error("Error creating meal:", error);
        res.status(500).json({ message: "Failed to create meal" });
      }
    }
  });

  app.get("/api/meals/:id", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const id = parseInt(req.params.id);
      if (isNaN(id)) {
        return res.status(400).json({ message: "Invalid meal ID" });
      }
      
      const meal = await storage.getMeal(id);
      if (!meal) {
        return res.status(404).json({ message: "Meal not found" });
      }
      
      res.json(meal);
    } catch (error) {
      console.error("Error getting meal:", error);
      res.status(500).json({ message: "Failed to get meal" });
    }
  });

  app.put("/api/meals/:id", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const id = parseInt(req.params.id);
      if (isNaN(id)) {
        return res.status(400).json({ message: "Invalid meal ID" });
      }
      
      const meal = await storage.getMeal(id);
      if (!meal) {
        return res.status(404).json({ message: "Meal not found" });
      }
      
      // Handle timestamp conversion for update
      const updateData = { ...req.body };
      if (updateData.timestamp && typeof updateData.timestamp === 'string') {
        try {
          updateData.timestamp = new Date(updateData.timestamp);
        } catch (e) {
          return res.status(400).json({ message: "Invalid timestamp format" });
        }
      }
      
      const updatedMeal = await storage.updateMeal(id, updateData);
      res.json(updatedMeal);
    } catch (error) {
      console.error("Error updating meal:", error);
      res.status(500).json({ message: "Failed to update meal" });
    }
  });

  app.delete("/api/meals/:id", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const id = parseInt(req.params.id);
      if (isNaN(id)) {
        return res.status(400).json({ message: "Invalid meal ID" });
      }
      
      // First check if the meal exists
      const meal = await storage.getMeal(id);
      if (!meal) {
        return res.status(404).json({ message: "Meal not found" });
      }
      
      // If it exists, delete it
      const success = await storage.deleteMeal(id);
      res.status(204).end();
    } catch (error) {
      console.error("Error deleting meal:", error);
      res.status(500).json({ message: "Failed to delete meal" });
    }
  });

  // Symptoms API
  app.get("/api/symptoms", isAuthenticated, async (req: any, res: Response) => {
    const userId = req.user.id;
    
    try {
      const symptoms = await storage.getSymptomsByUser(userId);
      res.json(symptoms);
    } catch (error) {
      console.error("Error getting symptoms:", error);
      res.status(500).json({ message: "Failed to get symptoms" });
    }
  });

  app.post("/api/symptoms", isAuthenticated, async (req: any, res: Response) => {
    const userId = req.user.id;
    
    try {
      const symptomData = { ...req.body, userId };
      const validatedData = insertSymptomSchema.parse(symptomData);
      const symptom = await storage.createSymptom(validatedData);
      res.status(201).json(symptom);
    } catch (error) {
      if (error instanceof z.ZodError) {
        res.status(400).json({ message: "Invalid symptom data", errors: error.errors });
      } else {
        console.error("Error creating symptom:", error);
        res.status(500).json({ message: "Failed to create symptom" });
      }
    }
  });

  app.get("/api/symptoms/:id", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const id = parseInt(req.params.id);
      if (isNaN(id)) {
        return res.status(400).json({ message: "Invalid symptom ID" });
      }
      
      const symptom = await storage.getSymptom(id);
      if (!symptom) {
        return res.status(404).json({ message: "Symptom not found" });
      }
      
      res.json(symptom);
    } catch (error) {
      console.error("Error getting symptom:", error);
      res.status(500).json({ message: "Failed to get symptom" });
    }
  });

  app.put("/api/symptoms/:id", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const id = parseInt(req.params.id);
      if (isNaN(id)) {
        return res.status(400).json({ message: "Invalid symptom ID" });
      }
      
      const symptom = await storage.getSymptom(id);
      if (!symptom) {
        return res.status(404).json({ message: "Symptom not found" });
      }
      
      const updatedSymptom = await storage.updateSymptom(id, req.body);
      res.json(updatedSymptom);
    } catch (error) {
      console.error("Error updating symptom:", error);
      res.status(500).json({ message: "Failed to update symptom" });
    }
  });

  app.delete("/api/symptoms/:id", isAuthenticated, async (req: Request, res: Response) => {
    try {
      const id = parseInt(req.params.id);
      if (isNaN(id)) {
        return res.status(400).json({ message: "Invalid symptom ID" });
      }
      
      const success = await storage.deleteSymptom(id);
      if (!success) {
        return res.status(404).json({ message: "Symptom not found" });
      }
      
      res.status(204).end();
    } catch (error) {
      console.error("Error deleting symptom:", error);
      res.status(500).json({ message: "Failed to delete symptom" });
    }
  });

  // Correlations API
  app.get("/api/correlations", isAuthenticated, async (req: any, res: Response) => {
    const userId = req.user.id;
    
    try {
      const correlations = await storage.getCorrelationsByUser(userId);
      
      // Filter out correlations with full meal names (containing separators) to show only individual ingredients
      const filteredCorrelations = correlations.filter(correlation => {
        const hasMultipleFoods = correlation.foodName.includes(',') || 
                                 correlation.foodName.includes('&') || 
                                 correlation.foodName.toLowerCase().includes(' and ') ||
                                 correlation.foodName.includes(' with ');
        return !hasMultipleFoods; // Only return individual foods, not combined meal names
      });
      
      res.json(filteredCorrelations);
    } catch (error) {
      console.error("Error getting correlations:", error);
      res.status(500).json({ message: "Failed to get correlations" });
    }
  });

  // Endpoint to regenerate correlations with improved parsing
  app.post("/api/correlations/regenerate", isAuthenticated, async (req: any, res: Response) => {
    const userId = req.user.id;
    
    try {
      await storage.regenerateCorrelations(userId);
      res.json({ message: "Correlations regenerated successfully" });
    } catch (error) {
      console.error("Error regenerating correlations:", error);
      res.status(500).json({ message: "Failed to regenerate correlations" });
    }
  });

  // Recent entries API (for dashboard)
  app.get("/api/entries/recent", isAuthenticated, async (req: any, res: Response) => {
    const userId = req.user.id;
    const daysToLookBack = parseInt(req.query.days as string) || 2;
    
    try {
      const lookbackDate = new Date();
      lookbackDate.setDate(lookbackDate.getDate() - daysToLookBack);
      
      const meals = await storage.getMealsByUserAndTimeRange(
        userId, 
        lookbackDate, 
        new Date()
      );
      
      const symptoms = await storage.getSymptomsByUserAndTimeRange(
        userId, 
        lookbackDate, 
        new Date()
      );
      
      // Combine and sort by timestamp, then deduplicate symptoms by name and date
      const entries = [
        ...meals.map(meal => ({
          ...meal,
          type: 'meal'
        })),
        ...symptoms.map(symptom => ({
          ...symptom,
          type: 'symptom'
        }))
      ].sort((a, b) => {
        return new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime();
      });
      
      // Group by day and deduplicate symptoms
      const groupedByDay = entries.reduce((acc, entry) => {
        const date = new Date(entry.timestamp);
        const dateStr = date.toISOString().split('T')[0];
        
        if (!acc[dateStr]) {
          acc[dateStr] = [];
        }
        
        // For symptoms, check if we already have this symptom for this date
        if (entry.type === 'symptom') {
          const existingSymptom = acc[dateStr].find(
            existing => existing.type === 'symptom' && existing.name === entry.name
          );
          
          if (!existingSymptom) {
            acc[dateStr].push(entry);
          }
        } else {
          // Always add meals
          acc[dateStr].push(entry);
        }
        
        return acc;
      }, {} as Record<string, any[]>);
      
      res.json(groupedByDay);
    } catch (error) {
      console.error("Error getting recent entries:", error);
      res.status(500).json({ message: "Failed to get recent entries" });
    }
  });

  // Get all entries for a specific date
  app.get("/api/entries/date", isAuthenticated, async (req: any, res: Response) => {
    try {
      const userId = req.user.id;
      const dateStr = req.query.date as string;
      
      if (!dateStr) {
        return res.status(400).json({ message: "Date parameter is required" });
      }
      
      // Parse date and create start/end of day timestamps
      const date = parse(dateStr, "yyyy-MM-dd", new Date());
      const start = startOfDay(date);
      const end = endOfDay(date);
      
      // Get meals and symptoms for the specified date
      const meals = await storage.getMealsByUserAndTimeRange(userId, start, end);
      const symptoms = await storage.getSymptomsByUserAndTimeRange(userId, start, end);
      
      res.json({
        date: dateStr,
        meals,
        symptoms
      });
    } catch (error) {
      console.error("Error getting entries for date:", error);
      res.status(500).json({ message: "Failed to get entries for specified date" });
    }
  });
  
  // Get markers for dates with entries (for calendar highlighting)
  app.get("/api/entries/markers", isAuthenticated, async (req: any, res: Response) => {
    try {
      const userId = req.user.id;
      const startDateStr = req.query.start as string;
      const endDateStr = req.query.end as string;
      
      if (!startDateStr || !endDateStr) {
        return res.status(400).json({ message: "Start and end date parameters are required" });
      }
      
      const startDate = new Date(startDateStr);
      const endDate = new Date(endDateStr);
      
      // Get all meals and symptoms for the date range
      const meals = await storage.getMealsByUserAndTimeRange(userId, startDate, endDate);
      const symptoms = await storage.getSymptomsByUserAndTimeRange(userId, startDate, endDate);
      
      // Create markers for days with entries
      const markers: Record<string, { meals: number; symptoms: number }> = {};
      
      // Process meals
      meals.forEach(meal => {
        const date = new Date(meal.timestamp).toISOString().split('T')[0];
        
        if (!markers[date]) {
          markers[date] = { meals: 0, symptoms: 0 };
        }
        
        markers[date].meals++;
      });
      
      // Process symptoms
      symptoms.forEach(symptom => {
        const date = new Date(symptom.timestamp).toISOString().split('T')[0];
        
        if (!markers[date]) {
          markers[date] = { meals: 0, symptoms: 0 };
        }
        
        markers[date].symptoms++;
      });
      
      res.json(markers);
    } catch (error) {
      console.error("Error getting entry markers:", error);
      res.status(500).json({ message: "Failed to get entry markers" });
    }
  });
  
  // Get monthly statistics
  app.get("/api/stats/monthly", isAuthenticated, async (req: any, res: Response) => {
    try {
      const userId = req.user.id;
      const startDateStr = req.query.start as string;
      const endDateStr = req.query.end as string;
      
      if (!startDateStr || !endDateStr) {
        return res.status(400).json({ message: "Start and end date parameters are required" });
      }
      
      const startDate = new Date(startDateStr);
      const endDate = new Date(endDateStr);
      
      // Get all meals and symptoms for the month
      const meals = await storage.getMealsByUserAndTimeRange(userId, startDate, endDate);
      const symptoms = await storage.getSymptomsByUserAndTimeRange(userId, startDate, endDate);
      
      // Create a set of unique dates that have entries
      const trackingDays = new Set<string>();
      
      // Count occurrences of each food and symptom
      const foodCounts: Record<string, number> = {};
      const symptomCounts: Record<string, number> = {};
      
      // Process meals
      meals.forEach(meal => {
        const date = new Date(meal.timestamp).toISOString().split('T')[0];
        trackingDays.add(date);
        
        // Count food occurrences
        if (!foodCounts[meal.name]) {
          foodCounts[meal.name] = 0;
        }
        foodCounts[meal.name]++;
        
        // Count ingredients too
        if (meal.ingredients) {
          meal.ingredients.forEach(ingredient => {
            if (!foodCounts[ingredient]) {
              foodCounts[ingredient] = 0;
            }
            foodCounts[ingredient]++;
          });
        }
      });
      
      // Process symptoms
      symptoms.forEach(symptom => {
        const date = new Date(symptom.timestamp).toISOString().split('T')[0];
        trackingDays.add(date);
        
        // Count symptom occurrences
        if (!symptomCounts[symptom.name]) {
          symptomCounts[symptom.name] = 0;
        }
        symptomCounts[symptom.name]++;
      });
      
      // Convert counts to sorted arrays
      const topFoods = Object.entries(foodCounts)
        .map(([name, count]) => ({ name, count }))
        .sort((a, b) => b.count - a.count)
        .slice(0, 5); // Top 5
      
      const topSymptoms = Object.entries(symptomCounts)
        .map(([name, count]) => ({ name, count }))
        .sort((a, b) => b.count - a.count)
        .slice(0, 5); // Top 5
      
      res.json({
        totalMeals: meals.length,
        totalSymptoms: symptoms.length,
        daysTracked: trackingDays.size,
        topFoods,
        topSymptoms
      });
    } catch (error) {
      console.error("Error generating monthly stats:", error);
      res.status(500).json({ message: "Failed to generate monthly statistics" });
    }
  });

}
