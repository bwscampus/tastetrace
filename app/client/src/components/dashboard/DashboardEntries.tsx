import { format } from "date-fns";
import { useLocation } from "wouter";
import { toast } from "@/hooks/use-toast";
import { Button } from "@/components/ui/button";
import { useMutation } from "@tanstack/react-query";
import { apiRequest, queryClient } from "@/lib/queryClient";

interface Entry {
  id: number;
  type: string;
  name: string;
  timestamp: string;
  date: string;
  mealType?: string;
  severity?: string;
  notes?: string;
  ingredients?: string[];
  isGlutenFree?: boolean;
  isDairyFree?: boolean;
  isGrainFree?: boolean;
  isSugarFree?: boolean;
}

interface DashboardEntriesProps {
  entries: Record<string, Entry[]>;
}

const DashboardEntries = ({ entries }: DashboardEntriesProps) => {
  const [, setLocation] = useLocation();
  
  // Get sorted dates (newest first)
  const sortedDates = Object.keys(entries).sort((a, b) => new Date(b).getTime() - new Date(a).getTime());
  
  // Delete mutation for meals
  const deleteMealMutation = useMutation({
    mutationFn: (id: number) => {
      return apiRequest("DELETE", `/api/meals/${id}`);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["/api/entries/recent"] });
      queryClient.invalidateQueries({ queryKey: ["/api/correlations"] });
      toast({
        title: "Entry deleted",
        description: "The meal entry has been removed",
      });
    },
    onError: () => {
      toast({
        title: "Error deleting entry",
        description: "There was a problem removing this entry",
        variant: "destructive",
      });
    },
  });

  // Delete mutation for symptoms
  const deleteSymptomMutation = useMutation({
    mutationFn: (id: number) => {
      return apiRequest("DELETE", `/api/symptoms/${id}`);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["/api/entries/recent"] });
      queryClient.invalidateQueries({ queryKey: ["/api/correlations"] });
      toast({
        title: "Entry deleted",
        description: "The symptom entry has been removed",
      });
    },
    onError: () => {
      toast({
        title: "Error deleting entry",
        description: "There was a problem removing this entry",
        variant: "destructive",
      });
    },
  });
  
  const handleEdit = (entry: Entry) => {
    // Store entry data in sessionStorage for the edit page to use
    sessionStorage.setItem('editEntry', JSON.stringify(entry));
    
    // Navigate to the appropriate edit page
    if (entry.type === 'meal') {
      setLocation(`/edit-meal/${entry.id}`);
    } else {
      setLocation(`/edit-symptom/${entry.id}`);
    }
  };
  
  const handleDelete = (entry: Entry) => {
    if (window.confirm(`Are you sure you want to delete this ${entry.type}?`)) {
      if (entry.type === 'meal') {
        deleteMealMutation.mutate(entry.id);
      } else {
        deleteSymptomMutation.mutate(entry.id);
      }
    }
  };
  
  const formatTimeFromISOString = (isoString: string) => {
    try {
      const date = new Date(isoString);
      if (isNaN(date.getTime())) {
        console.error("Invalid date:", isoString);
        return "Time unavailable";
      }
      return format(date, "h:mm a");
    } catch (error) {
      console.error("Error formatting date:", error);
      return "Time unavailable";
    }
  };
  
  const getHumanReadableDate = (dateString: string) => {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    
    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);
    
    const date = new Date(dateString);
    date.setHours(0, 0, 0, 0);
    
    if (date.getTime() === today.getTime()) {
      return "Today";
    } else if (date.getTime() === yesterday.getTime()) {
      return "Yesterday";
    } else {
      return format(date, "MMMM d, yyyy");
    }
  };

  return (
    <div className="space-y-4">
      {sortedDates.map((date) => (
        <div key={date}>
          <h3 className="font-medium text-gray-700 mb-2">{getHumanReadableDate(date)}</h3>
          <div className="bg-white rounded-lg shadow-sm p-4">
            {entries[date].map((entry) => (
              <div key={`${entry.type}-${entry.id}`} className="flex items-center justify-between mb-3 last:mb-0 pb-3 last:pb-0 border-b last:border-b-0">
                <div className="flex items-center">
                  <div 
                    className={`w-1 h-8 rounded-full mr-3 ${
                      entry.type === 'meal' ? 'bg-blue-500' : 'bg-yellow-500'
                    }`}
                  ></div>
                  <div>
                    <p className="font-medium">
                      {entry.type === 'meal' 
                        ? `${entry.mealType} - ${formatTimeFromISOString(entry.timestamp)}` 
                        : `Symptom - ${formatTimeFromISOString(entry.timestamp)}`
                      }
                    </p>
                    <p className="text-gray-500 text-sm">
                      {entry.type === 'meal' 
                        ? entry.name 
                        : `${entry.name} (${entry.severity})`
                      }
                    </p>
                  </div>
                </div>
                <div className="flex space-x-2">
                  <Button 
                    variant="outline" 
                    size="sm" 
                    className="text-xs border-navy text-navy"
                    onClick={() => handleEdit(entry)}
                  >
                    Edit
                  </Button>
                  <Button 
                    variant="outline" 
                    size="sm" 
                    className="text-xs text-red-600 border-red-600 hover:bg-red-50"
                    onClick={() => handleDelete(entry)}
                  >
                    Delete
                  </Button>
                </div>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
};

export default DashboardEntries;
