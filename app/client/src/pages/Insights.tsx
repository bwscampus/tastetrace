import { useQuery, useMutation } from "@tanstack/react-query";
import { useState, useEffect } from "react";
import { apiRequest } from "@/lib/queryClient";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Skeleton } from "@/components/ui/skeleton";
import InsightCard from "@/components/dashboard/InsightCard";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

// Define types for our component
interface Correlation {
  id: number;
  userId: number;
  foodName: string;
  symptomName: string;
  occurrences: number;
  confidence: number;
}

const Insights = () => {
  const [confidenceFilter, setConfidenceFilter] = useState<string>("all");
  const [isRegenerating, setIsRegenerating] = useState(false);
  
  const { data: correlations, isLoading, refetch } = useQuery<Correlation[]>({
    queryKey: ["/api/correlations"],
  });

  const regenerateCorrelations = useMutation({
    mutationFn: async () => {
      const res = await apiRequest("POST", "/api/correlations/regenerate");
      return await res.json();
    },
    onSuccess: () => {
      // Refetch correlations after regeneration
      refetch();
      setIsRegenerating(false);
    },
    onError: () => {
      setIsRegenerating(false);
    }
  });

  // Manual regeneration only - removed auto-regeneration to prevent infinite loops

  const filteredCorrelations = (): Correlation[] => {
    if (!correlations || !Array.isArray(correlations)) return [];
    
    return correlations.filter((correlation) => {
      if (confidenceFilter === "high") return correlation.confidence >= 70;
      if (confidenceFilter === "medium") return correlation.confidence >= 40 && correlation.confidence < 70;
      if (confidenceFilter === "low") return correlation.confidence < 40;
      return true; // "all"
    });
  };

  // Group correlations by symptom
  const groupedBySymptom = () => {
    const filtered = filteredCorrelations();
    const grouped: { [symptom: string]: Correlation[] } = {};
    
    filtered.forEach(correlation => {
      if (!grouped[correlation.symptomName]) {
        grouped[correlation.symptomName] = [];
      }
      grouped[correlation.symptomName].push(correlation);
    });
    
    // Sort foods within each symptom by confidence descending
    Object.keys(grouped).forEach(symptom => {
      grouped[symptom].sort((a, b) => b.confidence - a.confidence);
    });
    
    return grouped;
  };

  return (
    <div className="bg-light-blue min-h-screen py-12">
      <div className="container mx-auto px-4">
        <div className="flex justify-between items-center mb-8">
          <h1 className="text-2xl md:text-3xl font-bold text-navy">Food & Symptom Insights</h1>
          <div className="flex items-center gap-2">
            <span className="text-gray-600">Filter by:</span>
            <Select value={confidenceFilter} onValueChange={setConfidenceFilter}>
              <SelectTrigger className="w-[180px]">
                <SelectValue placeholder="Confidence Level" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Correlations</SelectItem>
                <SelectItem value="high">High Confidence (≥70%)</SelectItem>
                <SelectItem value="medium">Medium Confidence (40-69%)</SelectItem>
                <SelectItem value="low">Low Confidence (Less than 40%)</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>

        <Tabs defaultValue="correlations">
          <TabsList className="mb-6">
            <TabsTrigger value="correlations">Food-Symptom Correlations</TabsTrigger>
            <TabsTrigger value="info">Understanding Correlations</TabsTrigger>
          </TabsList>
          
          <TabsContent value="correlations">
            {isLoading ? (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                {[...Array(6)].map((_, index) => (
                  <Skeleton key={index} className="h-40" />
                ))}
              </div>
            ) : filteredCorrelations().length > 0 ? (
              <div className="space-y-8">
                {Object.entries(groupedBySymptom()).map(([symptom, correlations]) => (
                  <Card key={symptom} className="bg-white shadow-sm">
                    <CardHeader className="pb-4">
                      <CardTitle className="text-xl font-bold text-navy">{symptom}</CardTitle>
                      <CardDescription className="text-gray-600">
                        Foods that may be linked to this symptom
                      </CardDescription>
                    </CardHeader>
                    <CardContent>
                      <div className="space-y-4">
                        {correlations.map((correlation) => {
                          const getConfidenceColor = (confidence: number) => {
                            if (confidence >= 70) return 'text-red-600 bg-red-50';
                            if (confidence >= 40) return 'text-yellow-600 bg-yellow-50';
                            return 'text-blue-600 bg-blue-50';
                          };
                          
                          const getConfidenceLabel = (confidence: number) => {
                            if (confidence >= 70) return 'High';
                            if (confidence >= 40) return 'Medium';
                            return 'Low';
                          };
                          
                          return (
                            <div key={correlation.id} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                              <div className="flex-1">
                                <div className="font-medium text-gray-900">{correlation.foodName}</div>
                                <div className="text-sm text-gray-600">
                                  {correlation.occurrences} occurrence{correlation.occurrences > 1 ? 's' : ''}
                                </div>
                              </div>
                              <div className="text-right">
                                <div className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${getConfidenceColor(correlation.confidence)}`}>
                                  {getConfidenceLabel(correlation.confidence)} confidence
                                </div>
                                <div className="text-sm text-gray-500 mt-1">
                                  {correlation.confidence}%
                                </div>
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    </CardContent>
                  </Card>
                ))}
              </div>
            ) : (
              <Card>
                <CardContent className="pt-6">
                  <div className="text-center py-8">
                    <svg xmlns="http://www.w3.org/2000/svg" className="h-12 w-12 text-gray-400 mx-auto mb-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                    </svg>
                    <h3 className="text-lg font-medium text-gray-900 mb-2">No correlations found</h3>
                    <p className="text-gray-500 max-w-md mx-auto">
                      {confidenceFilter !== "all" 
                        ? `No correlations matching the selected confidence filter (${confidenceFilter}).`
                        : "Continue logging your meals and symptoms to discover potential connections between foods and how you feel."}
                    </p>
                  </div>
                </CardContent>
              </Card>
            )}
          </TabsContent>
          
          <TabsContent value="info">
            <Card>
              <CardHeader>
                <CardTitle>Understanding Food-Symptom Correlations</CardTitle>
                <CardDescription>
                  How TasteTrace analyzes your data to identify potential triggers
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div>
                  <h3 className="font-medium text-lg text-navy mb-2">How Correlations Work</h3>
                  <p className="text-gray-600">
                    When you log a symptom, TasteTrace automatically looks at the meals you've logged in the 
                    previous 12 hours. Our algorithm tracks how often a specific food appears before a symptom 
                    and calculates a confidence score based on this pattern.
                  </p>
                </div>
                
                <div>
                  <h3 className="font-medium text-lg text-navy mb-2">Confidence Scores</h3>
                  <p className="text-gray-600 mb-3">
                    Confidence scores represent how likely it is that a food and symptom are related:
                  </p>
                  <ul className="space-y-2 pl-5 list-disc text-gray-600">
                    <li><span className="font-medium text-red-500">High (≥70%)</span>: Strong evidence of a connection</li>
                    <li><span className="font-medium text-yellow-500">Medium (40-69%)</span>: Possible connection worth investigating</li>
                    <li><span className="font-medium text-blue-500">Low (Less than 40%)</span>: Weak connection, may be coincidental</li>
                  </ul>
                </div>
                
                <div>
                  <h3 className="font-medium text-lg text-navy mb-2">Sample Size & Reliability</h3>
                  <p className="text-gray-600 mb-3">
                    The number of times a symptom occurs after consuming a food affects how reliable our insights are:
                  </p>
                  <ul className="space-y-2 pl-5 list-disc text-gray-600">
                    <li><span className="font-medium text-green-600">High reliability (≥5 occurrences)</span>: Enough data to provide confident insights</li>
                    <li><span className="font-medium text-yellow-600">Moderate reliability (3-4 occurrences)</span>: Early pattern emerging but more data needed</li>
                    <li><span className="font-medium text-blue-600">Low reliability (1-2 occurrences)</span>: Not enough data yet for reliable conclusion</li>
                  </ul>
                  <p className="text-gray-600 mt-2 italic">
                    For more reliable insights, continue logging your meals and symptoms consistently.
                  </p>
                </div>
                
                <div>
                  <h3 className="font-medium text-lg text-navy mb-2">Important Notes</h3>
                  <ul className="space-y-2 pl-5 list-disc text-gray-600">
                    <li>Correlations are not the same as causation</li>
                    <li>More data leads to more accurate insights</li>
                    <li>Consider consulting a healthcare professional before making major dietary changes</li>
                    <li>Individual responses to foods vary greatly</li>
                  </ul>
                </div>
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </div>
    </div>
  );
};

export default Insights;
