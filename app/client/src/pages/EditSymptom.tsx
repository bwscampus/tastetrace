import { useEffect, useState } from "react";
import { useLocation } from "wouter";
import { useQuery, useMutation } from "@tanstack/react-query";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import SymptomForm from "@/components/symptom/SymptomForm";
import SymptomCard from "@/components/symptom/SymptomCard";
import { apiRequest, queryClient } from "@/lib/queryClient";
import { toast } from "@/hooks/use-toast";
import { SymptomSeverity } from "@shared/schema";
import { Label } from "@/components/ui/label";
import { ChevronLeft } from "lucide-react";
import { commonSymptoms } from "@/lib/constants";

const EditSymptom = () => {
  const [, setLocation] = useLocation();
  const [time, setTime] = useState<string>("");
  const [day, setDay] = useState<string>("");
  const [isLoading, setIsLoading] = useState(true);
  const [symptomId, setSymptomId] = useState<number | null>(null);
  const [notes, setNotes] = useState<string>("");
  const [selectedSymptoms, setSelectedSymptoms] = useState<
    Array<{ name: string; severity: SymptomSeverity }>
  >([]);

  // Get symptom ID from URL path
  useEffect(() => {
    const pathParts = window.location.pathname.split('/');
    const id = parseInt(pathParts[pathParts.length - 1]);
    if (!isNaN(id)) {
      setSymptomId(id);
    }
  }, []);

  // Load symptom data from sessionStorage or API
  useEffect(() => {
    try {
      const savedEntry = sessionStorage.getItem('editEntry');
      if (savedEntry) {
        const entry = JSON.parse(savedEntry);
        if (entry.type === 'symptom') {
          const timeStr = new Date(entry.timestamp).toTimeString().slice(0, 5);
          setTime(timeStr);
          
          // Format the date as yyyy-MM-dd for the date input
          const dateObj = new Date(entry.timestamp);
          const formattedDate = `${dateObj.getFullYear()}-${String(dateObj.getMonth() + 1).padStart(2, '0')}-${String(dateObj.getDate()).padStart(2, '0')}`;
          setDay(formattedDate);
          
          setSelectedSymptoms([{
            name: entry.name,
            severity: entry.severity as SymptomSeverity
          }]);
          
          setNotes(entry.notes || "");
          setIsLoading(false);
          sessionStorage.removeItem('editEntry'); // Clear after use
        }
      }
    } catch (error) {
      console.error("Error loading symptom data:", error);
    }
  }, []);

  // Fetch symptom data from API if not in sessionStorage
  const { data: symptomData } = useQuery({
    queryKey: ["/api/symptoms", symptomId],
    enabled: !!(symptomId && isLoading),
  });

  // Handle symptom data when it's loaded
  useEffect(() => {
    if (symptomData && isLoading) {
      const timeStr = new Date(symptomData.timestamp).toTimeString().slice(0, 5);
      setTime(timeStr);
      
      // Format the date as yyyy-MM-dd for the date input
      const dateObj = new Date(symptomData.timestamp);
      const formattedDate = `${dateObj.getFullYear()}-${String(dateObj.getMonth() + 1).padStart(2, '0')}-${String(dateObj.getDate()).padStart(2, '0')}`;
      setDay(formattedDate);
      
      setSelectedSymptoms([{
        name: symptomData.name,
        severity: symptomData.severity as SymptomSeverity
      }]);
      
      setNotes(symptomData.notes || "");
      setIsLoading(false);
    }
  }, [symptomData, isLoading]);

  const updateSymptomMutation = useMutation({
    mutationFn: (data: any) => {
      return apiRequest("PUT", `/api/symptoms/${symptomId}`, data);
    },
    onSuccess: () => {
      toast({
        title: "Symptom updated",
        description: "Your symptom has been successfully updated",
      });
      queryClient.invalidateQueries({ queryKey: ["/api/entries/recent"] });
      queryClient.invalidateQueries({ queryKey: ["/api/correlations"] });
      setLocation("/dashboard");
    },
    onError: () => {
      toast({
        title: "Error updating symptom",
        description: "There was a problem updating your symptom",
        variant: "destructive",
      });
    },
  });

  const toggleSymptom = (name: string, checked: boolean, severity: SymptomSeverity = SymptomSeverity.MILD) => {
    if (checked) {
      setSelectedSymptoms([...selectedSymptoms.filter(s => s.name !== name), { name, severity }]);
    } else {
      setSelectedSymptoms(selectedSymptoms.filter(s => s.name !== name));
    }
  };

  const updateSymptomSeverity = (name: string, severity: SymptomSeverity) => {
    setSelectedSymptoms(
      selectedSymptoms.map(s => (s.name === name ? { ...s, severity } : s))
    );
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    
    if (selectedSymptoms.length === 0) {
      toast({
        title: "No symptom selected",
        description: "Please select at least one symptom",
        variant: "destructive",
      });
      return;
    }
    
    // We're only editing one symptom at a time
    const symptom = selectedSymptoms[0];
    
    const [hours, minutes] = time.split(":");
    const date = new Date(day);
    date.setHours(parseInt(hours), parseInt(minutes), 0, 0);
    
    updateSymptomMutation.mutate({
      name: symptom.name,
      severity: symptom.severity,
      notes: notes,
      timestamp: date.toISOString(),
    });
  };

  // Sort symptoms alphabetically
  const sortedSymptoms = [...commonSymptoms].sort();

  return (
    <div className="bg-light-blue min-h-screen py-12">
      <div className="container mx-auto px-4">
        <Button
          variant="outline"
          className="mb-8 border-navy text-navy"
          onClick={() => setLocation("/dashboard")}
        >
          <ChevronLeft className="w-4 h-4 mr-2" />
          Back to Dashboard
        </Button>
        
        <div className="bg-white rounded-xl shadow-sm p-6 md:p-8 mb-8">
          <h1 className="text-2xl md:text-3xl font-bold text-navy mb-6">Edit Symptom</h1>
          
          <form onSubmit={handleSubmit} className="space-y-6">
            <SymptomForm
              time={time}
              setTime={setTime}
              day={day}
              setDay={setDay}
            />
            
            <div>
              <h3 className="text-lg font-medium mb-4">Select Your Symptom</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                {sortedSymptoms.map((symptom) => {
                  const selected = selectedSymptoms.find(s => s.name === symptom);
                  return (
                    <SymptomCard
                      key={symptom}
                      name={symptom}
                      isChecked={!!selected}
                      severity={selected?.severity || SymptomSeverity.MILD}
                      onToggle={(checked) => toggleSymptom(symptom, checked)}
                      onSeverityChange={(severity) => updateSymptomSeverity(symptom, severity)}
                    />
                  );
                })}
              </div>
            </div>
            
            <div className="space-y-3">
              <Label htmlFor="notes">Notes</Label>
              <Textarea
                id="notes"
                placeholder="Any additional notes about this symptom"
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                className="w-full"
              />
            </div>
            
            <Button 
              type="submit" 
              className="w-full bg-navy hover:bg-navy/90"
              disabled={updateSymptomMutation.isPending}
            >
              {updateSymptomMutation.isPending ? "Updating..." : "Update Symptom"}
            </Button>
          </form>
        </div>
      </div>
    </div>
  );
};

export default EditSymptom;