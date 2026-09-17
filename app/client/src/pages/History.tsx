import { useState } from "react";
import { format } from "date-fns";
import EntriesCalendar from "@/components/calendar/EntriesCalendar";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useQuery } from "@tanstack/react-query";
import { Skeleton } from "@/components/ui/skeleton";
import { 
  Card, 
  CardContent, 
  CardDescription, 
  CardHeader, 
  CardTitle 
} from "@/components/ui/card";

const History = () => {
  const [selectedDate, setSelectedDate] = useState<Date>(new Date());
  const [activeTab, setActiveTab] = useState<string>("calendar");

  // Get stats for the selected month
  const startOfMonth = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), 1);
  const endOfMonth = new Date(selectedDate.getFullYear(), selectedDate.getMonth() + 1, 0);
  
  const { data: monthlyStats, isLoading: isStatsLoading } = useQuery({
    queryKey: ["/api/stats/monthly", startOfMonth.toISOString(), endOfMonth.toISOString()],
    queryFn: async () => {
      const res = await fetch(`/api/stats/monthly?start=${startOfMonth.toISOString()}&end=${endOfMonth.toISOString()}`);
      if (!res.ok) throw new Error('Failed to fetch monthly stats');
      return res.json();
    },
    refetchOnMount: true,
    refetchOnWindowFocus: true,
    staleTime: 10000 // Consider data stale after 10 seconds
  });

  const handleDateSelect = (date: Date) => {
    setSelectedDate(date);
  };

  return (
    <div className="bg-light-blue min-h-screen py-12">
      <div className="container mx-auto px-4">
        <h1 className="text-2xl md:text-3xl font-bold text-navy mb-8">Your History</h1>
        
        <Tabs defaultValue="calendar" onValueChange={setActiveTab} className="mb-8">
          <TabsList className="grid w-full max-w-md grid-cols-2">
            <TabsTrigger value="calendar">Calendar View</TabsTrigger>
            <TabsTrigger value="stats">Monthly Stats</TabsTrigger>
          </TabsList>
          
          <TabsContent value="calendar" className="mt-6">
            <EntriesCalendar onSelectDate={handleDateSelect} />
          </TabsContent>
          
          <TabsContent value="stats" className="mt-6">
            <Card>
              <CardHeader>
                <CardTitle>Monthly Overview</CardTitle>
                <CardDescription>
                  {format(startOfMonth, "MMMM yyyy")}
                </CardDescription>
              </CardHeader>
              <CardContent>
                {isStatsLoading ? (
                  <div className="space-y-4">
                    <Skeleton className="h-16 w-full" />
                    <Skeleton className="h-16 w-full" />
                    <Skeleton className="h-16 w-full" />
                  </div>
                ) : (
                  <div className="space-y-6">
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                      <div className="bg-blue-50 p-4 rounded-lg">
                        <div className="text-sm text-gray-500">Total Meals</div>
                        <div className="text-2xl font-bold text-navy">{monthlyStats?.totalMeals || 0}</div>
                      </div>
                      <div className="bg-yellow-50 p-4 rounded-lg">
                        <div className="text-sm text-gray-500">Total Symptoms</div>
                        <div className="text-2xl font-bold text-navy">{monthlyStats?.totalSymptoms || 0}</div>
                      </div>
                      <div className="bg-green-50 p-4 rounded-lg">
                        <div className="text-sm text-gray-500">Tracking Days</div>
                        <div className="text-2xl font-bold text-navy">{monthlyStats?.daysTracked || 0}</div>
                      </div>
                    </div>
                    
                    {monthlyStats?.topFoods?.length > 0 && (
                      <div>
                        <h3 className="text-lg font-medium mb-3">Most Common Foods</h3>
                        <ul className="space-y-2">
                          {monthlyStats.topFoods.map((food: any, index: number) => (
                            <li key={index} className="flex justify-between items-center p-2 bg-white rounded-md">
                              <span>{food.name}</span>
                              <span className="text-gray-500">{food.count} times</span>
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}
                    
                    {monthlyStats?.topSymptoms?.length > 0 && (
                      <div>
                        <h3 className="text-lg font-medium mb-3">Most Common Symptoms</h3>
                        <ul className="space-y-2">
                          {monthlyStats.topSymptoms.map((symptom: any, index: number) => (
                            <li key={index} className="flex justify-between items-center p-2 bg-white rounded-md">
                              <span>{symptom.name}</span>
                              <span className="text-gray-500">{symptom.count} times</span>
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}
                  </div>
                )}
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </div>
    </div>
  );
};

export default History;