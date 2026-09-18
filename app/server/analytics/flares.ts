import { Meal, Symptom } from "@shared/schema";

// Symptoms logged within this many minutes of the first one are one flare
export const FLARE_CLUSTER_MINUTES = 30;

export type Flare = {
  start: Date;
  end: Date;
  symptoms: Symptom[];
  names: string[];
  maxIntensity: number;
};

export function intensityOf(symptom: Symptom): number {
  if (symptom.intensity != null) return symptom.intensity;
  switch (symptom.severity) {
    case "Mild": return 2;
    case "Severe": return 4;
    default: return 3;
  }
}

/** Groups symptoms (any order) into flares. */
export function clusterFlares(symptoms: Symptom[]): Flare[] {
  const sorted = [...symptoms].sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());
  const flares: Flare[] = [];
  const windowMs = FLARE_CLUSTER_MINUTES * 60 * 1000;
  for (const symptom of sorted) {
    const current = flares[flares.length - 1];
    if (current && symptom.timestamp.getTime() - current.start.getTime() <= windowMs) {
      current.symptoms.push(symptom);
      current.end = symptom.timestamp;
      if (!current.names.includes(symptom.name)) current.names.push(symptom.name);
      current.maxIntensity = Math.max(current.maxIntensity, intensityOf(symptom));
    } else {
      flares.push({ start: symptom.timestamp, end: symptom.timestamp, symptoms: [symptom], names: [symptom.name], maxIntensity: intensityOf(symptom) });
    }
  }
  return flares;
}

export function hoursBetween(earlier: Date, later: Date): number {
  return (later.getTime() - earlier.getTime()) / 3_600_000;
}

/** Meals eaten in the `windowHours` before `at`, most recent first. */
export function mealsBefore(meals: Meal[], at: Date, windowHours: number): Meal[] {
  return meals
    .filter((m) => {
      const h = hoursBetween(m.timestamp, at);
      return h > 0 && h <= windowHours;
    })
    .sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime());
}

/** Hours from the most recent prior meal (within the window), or null. */
export function onsetHours(meals: Meal[], at: Date, windowHours: number): number | null {
  const [latest] = mealsBefore(meals, at, windowHours);
  return latest ? hoursBetween(latest.timestamp, at) : null;
}
