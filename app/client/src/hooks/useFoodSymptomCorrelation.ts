import { useState, useEffect } from "react";
import { useQuery } from "@tanstack/react-query";

interface Meal {
  id: number;
  name: string;
  timestamp: string;
}

interface Symptom {
  id: number;
  name: string;
  severity: string;
  timestamp: string;
}

interface Correlation {
  id: number;
  food: string;
  symptom: string;
  confidence: number;
  occurrences: number;
}

export function useFoodSymptomCorrelation() {
  const { data: meals, isLoading: isMealsLoading } = useQuery({
    queryKey: ["/api/meals"],
  });

  const { data: symptoms, isLoading: isSymptomsLoading } = useQuery({
    queryKey: ["/api/symptoms"],
  });

  const { data: correlations, isLoading: isCorrelationsLoading } = useQuery({
    queryKey: ["/api/correlations"],
  });

  const isLoading = isMealsLoading || isSymptomsLoading || isCorrelationsLoading;

  return {
    meals,
    symptoms,
    correlations,
    isLoading,
  };
}
