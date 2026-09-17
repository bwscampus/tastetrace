import { useQuery } from "@tanstack/react-query";
import { Link } from "wouter";
import { Button } from "@/components/ui/button";
import DashboardEntries from "@/components/dashboard/DashboardEntries";
import InsightCard from "@/components/dashboard/InsightCard";
import { Skeleton } from "@/components/ui/skeleton";

const Dashboard = () => {
  const { data: entriesData, isLoading: isEntriesLoading } = useQuery({
    queryKey: ["/api/entries/recent"],
  });

  const { data: correlations, isLoading: isCorrelationsLoading } = useQuery({
    queryKey: ["/api/correlations"],
  });

  return (
    <div className="bg-light-blue min-h-screen py-12">
      <div className="container mx-auto px-4">
        <div className="flex justify-between items-center mb-8">
          <h1 className="text-2xl md:text-3xl font-bold text-navy">Your Dashboard</h1>
          <div className="flex gap-3">
            <Button asChild variant="outline" className="border-navy text-navy">
              <Link href="/log-meal">Log Meal</Link>
            </Button>
            <Button asChild className="bg-navy hover:bg-navy/90">
              <Link href="/log-symptom">Log Symptom</Link>
            </Button>
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          <div className="lg:col-span-2">
            <div className="bg-white rounded-xl shadow-sm p-6 mb-8">
              <h2 className="text-xl font-semibold text-navy mb-4">Recent Entries</h2>
              {isEntriesLoading ? (
                <div className="space-y-4">
                  {[...Array(3)].map((_, index) => (
                    <div key={index} className="space-y-2">
                      <Skeleton className="h-6 w-40" />
                      <Skeleton className="h-24 w-full" />
                    </div>
                  ))}
                </div>
              ) : Object.keys(entriesData || {}).length ? (
                <DashboardEntries entries={entriesData} />
              ) : (
                <div className="text-center py-8">
                  <p className="text-gray-500 mb-4">No entries yet. Start tracking your meals and symptoms!</p>
                  <div className="flex flex-col sm:flex-row gap-3 justify-center">
                    <Button asChild variant="outline" className="border-navy text-navy">
                      <Link href="/log-meal">Log Your First Meal</Link>
                    </Button>
                    <Button asChild className="bg-navy hover:bg-navy/90">
                      <Link href="/log-symptom">Log a Symptom</Link>
                    </Button>
                  </div>
                </div>
              )}
            </div>
          </div>

          <div>
            <div className="bg-white rounded-xl shadow-sm p-6">
              <h2 className="text-xl font-semibold text-navy mb-4">Potential Insights</h2>
              {isCorrelationsLoading ? (
                <div className="space-y-4">
                  {[...Array(2)].map((_, index) => (
                    <Skeleton key={index} className="h-32 w-full" />
                  ))}
                </div>
              ) : correlations?.length > 0 ? (
                <div className="space-y-4">
                  {correlations
                    .filter((correlation: any) => correlation.confidence > 30)
                    .slice(0, 3)
                    .map((correlation: any) => (
                      <InsightCard 
                        key={correlation.id} 
                        food={correlation.foodName} 
                        symptom={correlation.symptomName} 
                        confidence={correlation.confidence}
                        occurrences={correlation.occurrences} 
                      />
                    ))}
                    
                    <div className="text-center mt-6">
                      <Link href="/insights">
                        <a className="text-blue-600 font-medium hover:underline">View All Insights</a>
                      </Link>
                    </div>
                </div>
              ) : (
                <div className="bg-white rounded-lg shadow-sm p-4">
                  <div className="flex items-start">
                    <div className="w-10 h-10 rounded-full bg-navy bg-opacity-20 flex items-center justify-center mr-3 mt-1">
                      <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 text-navy" viewBox="0 0 20 20" fill="currentColor">
                        <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                      </svg>
                    </div>
                    <div>
                      <p className="font-medium text-navy">Continue logging to discover patterns</p>
                      <p className="text-gray-500">We need more data to provide meaningful insights</p>
                    </div>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Dashboard;
