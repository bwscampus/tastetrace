import { useState } from "react";
import { format } from "date-fns";
import { Calendar as CalendarComponent } from "@/components/ui/calendar";
import { 
  Card, 
  CardContent, 
  CardHeader, 
  CardTitle 
} from "@/components/ui/card";
import { useQuery } from "@tanstack/react-query";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import { UtensilsCrossed, AlertCircle } from "lucide-react";

interface EntriesCalendarProps {
  onSelectDate: (date: Date) => void;
}

const EntriesCalendar = ({ onSelectDate }: EntriesCalendarProps) => {
  const [date, setDate] = useState<Date | undefined>(new Date());
  
  // Get markers for dates with entries for the current month to highlight on calendar
  const startOfMonth = new Date(date?.getFullYear() || new Date().getFullYear(), date?.getMonth() || new Date().getMonth(), 1);
  const endOfMonth = new Date(date?.getFullYear() || new Date().getFullYear(), (date?.getMonth() || new Date().getMonth()) + 1, 0);
  
  const { data: entryMarkers, isLoading: isMarkersLoading } = useQuery({
    queryKey: ["/api/entries/markers", startOfMonth.toISOString(), endOfMonth.toISOString()],
    queryFn: async () => {
      const res = await fetch(`/api/entries/markers?start=${startOfMonth.toISOString()}&end=${endOfMonth.toISOString()}`);
      if (!res.ok) throw new Error('Failed to fetch markers');
      return res.json();
    },
    refetchOnMount: true, // Force refetch when component mounts
    refetchOnWindowFocus: true // Refetch when window regains focus
  });
  
  // Get detailed entries for the selected date
  const selectedDateStr = date ? format(date, "yyyy-MM-dd") : "";
  // Define a type for the day entries response
  type DayEntriesResponse = {
    date: string;
    meals: any[];
    symptoms: any[];
  };

  const { data: dayEntries, isLoading: isEntriesLoading } = useQuery<DayEntriesResponse>({
    queryKey: ["/api/entries/date", selectedDateStr],
    queryFn: async () => {
      const res = await fetch(`/api/entries/date?date=${selectedDateStr}`);
      if (!res.ok) throw new Error('Failed to fetch day entries');
      return res.json();
    },
    enabled: !!selectedDateStr,
    refetchOnMount: true,
    refetchOnWindowFocus: true,
    staleTime: 10000 // Consider data stale after 10 seconds to encourage refetching
  });
  
  // Custom day render function to show markers for days with entries
  type MarkerData = Record<string, { meals: number; symptoms: number }>;
  
  // Custom day content to add markers
  const DayContent = (props: any) => {
    const { date } = props;
    
    if (!date) return null;
    
    const dateString = format(date, "yyyy-MM-dd");
    const markers = entryMarkers?.[dateString];
    const hasMeals = markers?.meals > 0;
    const hasSymptoms = markers?.symptoms > 0;
    
    return (
      <div className="relative">
        {date.getDate()}
        {(hasMeals || hasSymptoms) && (
          <div className="absolute -bottom-1 left-1/2 transform -translate-x-1/2 flex gap-0.5">
            {hasMeals && <div className="w-1 h-1 bg-blue-500 rounded-full"></div>}
            {hasSymptoms && <div className="w-1 h-1 bg-yellow-500 rounded-full"></div>}
          </div>
        )}
      </div>
    );
  };
  
  const handleDateChange = (newDate: Date | undefined) => {
    setDate(newDate);
    if (newDate) {
      onSelectDate(newDate);
    }
  };
  
  return (
    <div className="space-y-6">
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-xl">Entry History</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex flex-col md:flex-row md:space-x-6">
            <div className="md:w-1/2">
              <CalendarComponent
                mode="single"
                selected={date}
                onSelect={handleDateChange}
                className="rounded-md border"
                components={{
                  DayContent: DayContent
                }}
              />
              
              <div className="mt-3 flex items-center justify-center space-x-6">
                <div className="flex items-center space-x-2">
                  <div className="h-3 w-3 rounded-full bg-blue-500"></div>
                  <span className="text-sm text-gray-600">Meals</span>
                </div>
                <div className="flex items-center space-x-2">
                  <div className="h-3 w-3 rounded-full bg-yellow-500"></div>
                  <span className="text-sm text-gray-600">Symptoms</span>
                </div>
              </div>
            </div>
            
            <div className="mt-6 md:mt-0 md:w-1/2">
              <h3 className="font-medium text-base mb-3">
                {date ? format(date, "MMMM d, yyyy") : "Select a date"}
              </h3>
              
              {isEntriesLoading ? (
                <div className="space-y-3">
                  <Skeleton className="h-16 w-full" />
                  <Skeleton className="h-16 w-full" />
                </div>
              ) : dayEntries && ((dayEntries.meals && dayEntries.meals.length > 0) || (dayEntries.symptoms && dayEntries.symptoms.length > 0)) ? (
                <div className="space-y-4">
                  {dayEntries?.meals?.length > 0 && (
                    <div>
                      <h4 className="text-sm font-medium flex items-center">
                        <UtensilsCrossed className="w-4 h-4 mr-2" /> 
                        Meals
                      </h4>
                      <Separator className="my-2" />
                      <ul className="space-y-2">
                        {dayEntries.meals.map((meal: any) => (
                          <li key={meal.id} className="text-sm">
                            <div className="flex justify-between">
                              <span className="font-medium">{meal.name}</span>
                              <span className="text-gray-500">{format(new Date(meal.timestamp), "h:mm a")}</span>
                            </div>
                            <div className="text-xs text-gray-600 mt-1">
                              <Badge variant="outline" className="mr-1">{meal.mealType}</Badge>
                              {meal.containsGluten && <Badge variant="outline" className="bg-red-50 text-red-700 mr-1">Contains Gluten</Badge>}
                              {meal.containsDairy && <Badge variant="outline" className="bg-red-50 text-red-700 mr-1">Contains Dairy</Badge>}
                              {meal.containsGrains && <Badge variant="outline" className="bg-red-50 text-red-700 mr-1">Contains Grains</Badge>}
                              {meal.containsSugar && <Badge variant="outline" className="bg-red-50 text-red-700 mr-1">Contains Sugar</Badge>}
                              {meal.containsNuts && <Badge variant="outline" className="bg-red-50 text-red-700 mr-1">Contains Nuts</Badge>}
                            </div>
                          </li>
                        ))}
                      </ul>
                    </div>
                  )}
                  
                  {dayEntries?.symptoms?.length > 0 && (
                    <div>
                      <h4 className="text-sm font-medium flex items-center">
                        <AlertCircle className="w-4 h-4 mr-2" /> 
                        Symptoms
                      </h4>
                      <Separator className="my-2" />
                      <ul className="space-y-2">
                        {dayEntries.symptoms.map((symptom: any) => (
                          <li key={symptom.id} className="text-sm">
                            <div className="flex justify-between">
                              <span className="font-medium">{symptom.name}</span>
                              <span className="text-gray-500">{format(new Date(symptom.timestamp), "h:mm a")}</span>
                            </div>
                            <div className="text-xs text-gray-600 mt-1">
                              <Badge 
                                variant="outline" 
                                className={`${
                                  symptom.severity === "Severe" ? "bg-red-50 text-red-700" :
                                  symptom.severity === "Moderate" ? "bg-orange-50 text-orange-700" :
                                  "bg-yellow-50 text-yellow-700"
                                }`}
                              >
                                {symptom.severity}
                              </Badge>
                            </div>
                          </li>
                        ))}
                      </ul>
                    </div>
                  )}
                </div>
              ) : (
                <div className="text-center py-6 text-gray-500">
                  <div className="mb-2">No entries for this date</div>
                  <div className="text-sm">Select a date with markers to view entries</div>
                </div>
              )}
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};

export default EntriesCalendar;