import { SymptomSeverity } from "./schema";

// The web app records severity as Mild/Moderate/Severe; the mobile app
// records intensity 1-5. Both are stored on every symptom.
export function severityFromIntensity(intensity: number): SymptomSeverity {
  if (intensity <= 2) return SymptomSeverity.MILD;
  if (intensity === 3) return SymptomSeverity.MODERATE;
  return SymptomSeverity.SEVERE;
}

export function intensityFromSeverity(severity: string): number {
  switch (severity) {
    case SymptomSeverity.MILD: return 2;
    case SymptomSeverity.SEVERE: return 4;
    default: return 3;
  }
}

// Discomfort score on the 0-10 scale used by the digests
export function discomfortScore(intensity: number): number {
  return intensity * 2;
}
