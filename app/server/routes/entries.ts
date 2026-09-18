import type { Express, Request, Response } from "express";
import { storage } from "../storage";
import { isAuthenticated } from "../auth";
import { startOfDay, endOfDay, parse } from "date-fns";

// Correlations, dashboard/calendar entry views and monthly stats. These keep
// the shapes the web client expects.
export function registerEntryRoutes(app: Express) {
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
