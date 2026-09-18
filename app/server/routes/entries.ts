import type { Express, Request, Response } from "express";
import { storage } from "../storage";
import { isAuthenticated } from "../auth";
import { parse } from "date-fns";
import { dayBounds, isIsoDate, localDate, parseInstant } from "../analytics/time";
import { resolveTimezone } from "./context";
import { presentSymptom } from "./symptoms";
import { Symptom } from "@shared/schema";

// Symptoms within 30 minutes of each other count as one flare
const FLARE_CLUSTER_MS = 30 * 60 * 1000;
export function countFlares(symptoms: Symptom[]): number {
  const times = symptoms.map((s) => s.timestamp.getTime()).sort((a, b) => a - b);
  let flares = 0;
  let clusterStart = -Infinity;
  for (const t of times) {
    if (t - clusterStart > FLARE_CLUSTER_MS) {
      flares++;
      clusterStart = t;
    }
  }
  return flares;
}

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

  // Get all entries for a specific local date
  app.get("/api/entries/date", isAuthenticated, async (req: any, res: Response) => {
    try {
      const userId = req.user.id;
      const dateStr = req.query.date as string;
      
      if (!dateStr) {
        return res.status(400).json({ message: "Date parameter is required" });
      }
      if (!isIsoDate(dateStr)) {
        return res.status(400).json({ message: "Date must be YYYY-MM-DD" });
      }

      const tz = await resolveTimezone(req);
      const { start, end } = dayBounds(dateStr, tz);
      end.setMilliseconds(end.getMilliseconds() - 1);
      
      // Get meals and symptoms for the specified date
      const meals = await storage.getMealsByUserAndTimeRange(userId, start, end);
      const symptoms = await storage.getSymptomsByUserAndTimeRange(userId, start, end);
      const custom = await storage.getCustomSymptoms(userId);
      
      res.json({
        date: dateStr,
        meals,
        symptoms: symptoms.map((s) => presentSymptom(s, custom)),
        flares: countFlares(symptoms),
        entries: meals.length + symptoms.length,
      });
    } catch (error) {
      console.error("Error getting entries for date:", error);
      res.status(500).json({ message: "Failed to get entries for specified date" });
    }
  });
  
  // Get markers for dates with entries (calendar / week strip decoration)
  app.get("/api/entries/markers", isAuthenticated, async (req: any, res: Response) => {
    try {
      const userId = req.user.id;
      const startDate = parseInstant(req.query.start);
      const endDate = parseInstant(req.query.end);
      
      if (!req.query.start || !req.query.end) {
        return res.status(400).json({ message: "Start and end date parameters are required" });
      }
      if (!startDate || !endDate) {
        return res.status(400).json({ message: "Start and end must be ISO dates" });
      }

      const tz = await resolveTimezone(req);
      const meals = await storage.getMealsByUserAndTimeRange(userId, startDate, endDate);
      const symptoms = await storage.getSymptomsByUserAndTimeRange(userId, startDate, endDate);
      
      const markers: Record<string, { meals: number; symptoms: number; maxIntensity: number; status: "ok" | "meal" | "symptom" }> = {};
      const marker = (date: string) => (markers[date] ??= { meals: 0, symptoms: 0, maxIntensity: 0, status: "ok" });

      meals.forEach((meal) => {
        marker(localDate(meal.timestamp, tz)).meals++;
      });
      symptoms.forEach((symptom) => {
        const m = marker(localDate(symptom.timestamp, tz));
        m.symptoms++;
        m.maxIntensity = Math.max(m.maxIntensity, symptom.intensity ?? 0);
      });
      for (const m of Object.values(markers)) {
        m.status = m.symptoms > 0 ? "symptom" : m.meals > 0 ? "meal" : "ok";
      }
      
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
