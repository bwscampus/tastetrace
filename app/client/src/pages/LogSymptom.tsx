import { useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { queryClient, apiRequest } from "@/lib/queryClient";
import { useLocation } from "wouter";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/hooks/use-toast";
import SymptomForm from "@/components/symptom/SymptomForm";
import SymptomCard from "@/components/symptom/SymptomCard";
import { commonSymptoms } from "@/lib/constants";
import { SymptomSeverity } from "@shared/schema";

const LogSymptom = () => {
  const [_, navigate] = useLocation();
  const [showSymptomSelection, setShowSymptomSelection] = useState(false);
  const [selectedSymptoms, setSelectedSymptoms] = useState<
    Array<{ name: string; severity: SymptomSeverity }>
  >([]);
  const [time, setTime] = useState(() => {
    const now = new Date();
    const hours = now.getHours().toString().padStart(2, "0");
    const minutes = now.getMinutes().toString().padStart(2, "0");
    return `${hours}:${minutes}`;
  });
  const [day, setDay] = useState("Today");
  const [notes, setNotes] = useState("");

  // Mutation for creating a symptom
  const symptomMutation = useMutation({
    mutationFn: (symptomData: any) => {
      return apiRequest("POST", "/api/symptoms", symptomData);
    },
    onSuccess: () => {
      // Invalidate and refetch
      queryClient.invalidateQueries({ queryKey: ["/api/symptoms"] });
      queryClient.invalidateQueries({ queryKey: ["/api/entries/recent"] });
      queryClient.invalidateQueries({ queryKey: ["/api/correlations"] });
      
      toast({
        title: "Symptoms saved successfully!",
        description: "Your symptoms have been logged.",
      });
      
      navigate("/dashboard");
    },
    onError: (error: any) => {
      toast({
        title: "Failed to save symptoms",
        description: error.message || "Please try again.",
        variant: "destructive",
      });
    },
  });

  const toggleSymptom = (name: string, checked: boolean, specificType?: string, severity: SymptomSeverity = SymptomSeverity.MILD) => {
    if (checked) {
      // For abnormal bowel movements, use the specific type as the symptom name
      const symptomName = name === "Abnormal bowel movements" && specificType ? specificType : name;
      setSelectedSymptoms(prev => {
        // Remove any existing entry with the base name first
        const filtered = prev.filter(s => s.name !== name && s.name !== specificType);
        return [...filtered, { name: symptomName, severity }];
      });
    } else {
      setSelectedSymptoms(prev => prev.filter(s => s.name !== name && s.name !== specificType));
    }
  };

  const updateSymptomSeverity = (name: string, severity: SymptomSeverity) => {
    setSelectedSymptoms(prev => 
      prev.map(s => {
        if (s.name === name) return { ...s, severity };
        // Handle bowel movement sub-types
        if (name === "Abnormal bowel movements" && (s.name === "Constipation" || s.name === "Diarrhea")) {
          return { ...s, severity };
        }
        return s;
      })
    );
  };

  const handleSaveSymptoms = () => {
    if (selectedSymptoms.length === 0) {
      toast({
        title: "No symptoms selected",
        description: "Please select at least one symptom.",
        variant: "destructive",
      });
      return;
    }
    
    // Create a timestamp
    const timestamp = createTimestampFromTimeString(time, day);
    
    // Submit each selected symptom
    const promises = selectedSymptoms.map(symptom => {
      const symptomData = {
        name: symptom.name,
        severity: symptom.severity,
        notes,
        timestamp,
      };
      
      return symptomMutation.mutateAsync(symptomData);
    });
    
    Promise.all(promises)
      .then(() => {
        toast({
          title: "Symptoms saved successfully!",
          description: `${selectedSymptoms.length} symptom(s) logged.`,
        });
        navigate("/dashboard");
      })
      .catch((error) => {
        toast({
          title: "Error saving symptoms",
          description: error.message || "Please try again.",
          variant: "destructive",
        });
      });
  };

  const createTimestampFromTimeString = (timeString: string, day: string) => {
    const [hours, minutes] = timeString.split(":").map(Number);
    const date = new Date();
    
    if (day === "Yesterday") {
      date.setDate(date.getDate() - 1);
    }
    
    date.setHours(hours, minutes, 0, 0);
    return date.toISOString();
  };

  return (
    <section className="py-12 bg-light-blue">
      <div className="container mx-auto px-4">
        <h1 className="text-2xl md:text-3xl font-bold text-navy mb-8">Log Your Symptoms</h1>
        
        {/* Did you experience symptoms today? */}
        <div className="bg-white p-6 rounded-xl shadow-sm mb-8">
          <h2 className="text-xl font-semibold text-navy mb-4">Did you experience any symptoms today?</h2>
          <div className="flex gap-4">
            <Button
              className={`flex-1 ${
                showSymptomSelection 
                  ? "bg-blue-500 text-white" 
                  : "bg-white text-navy border border-gray-300"
              }`}
              onClick={() => setShowSymptomSelection(true)}
            >
              Yes
            </Button>
            <Button
              className={`flex-1 ${
                !showSymptomSelection 
                  ? "bg-blue-500 text-white" 
                  : "bg-white text-navy border border-gray-300"
              }`}
              onClick={() => setShowSymptomSelection(false)}
            >
              No
            </Button>
          </div>
        </div>
        
        {/* Symptom selection */}
        {showSymptomSelection && (
          <div className="bg-white p-6 rounded-xl shadow-sm mb-8">
            <h2 className="text-xl font-semibold text-navy mb-4">Select your symptoms</h2>
            
            <div className="mb-6">
              <label className="block text-gray-700 font-medium mb-2">Common symptoms</label>
              <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
                {commonSymptoms.map((symptom) => (
                  <SymptomCard
                    key={symptom}
                    name={symptom}
                    isChecked={selectedSymptoms.some(s => s.name === symptom || (symptom === "Abnormal bowel movements" && (s.name === "Constipation" || s.name === "Diarrhea")))}
                    severity={selectedSymptoms.find(s => s.name === symptom || (symptom === "Abnormal bowel movements" && (s.name === "Constipation" || s.name === "Diarrhea")))?.severity || SymptomSeverity.MILD}
                    onToggle={(checked, specificType) => toggleSymptom(symptom, checked, specificType)}
                    onSeverityChange={(severity) => updateSymptomSeverity(symptom, severity)}
                  />
                ))}
              </div>
            </div>
            
            <div className="mb-6">
              <label className="block text-gray-700 font-medium mb-2">When did symptoms start?</label>
              <div className="flex gap-3">
                <Input
                  type="time"
                  value={time}
                  onChange={(e) => setTime(e.target.value)}
                  className="w-32"
                />
                <Select value={day} onValueChange={setDay}>
                  <SelectTrigger className="w-32">
                    <SelectValue placeholder="Select day" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Today">Today</SelectItem>
                    <SelectItem value="Yesterday">Yesterday</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
            
            <div className="mb-6">
              <label htmlFor="symptom-notes" className="block text-gray-700 font-medium mb-2">
                Notes (optional)
              </label>
              <Textarea
                id="symptom-notes"
                rows={2}
                placeholder="Add any details about your symptoms"
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
              />
            </div>
            
            <div className="flex justify-end">
              <Button 
                onClick={handleSaveSymptoms}
                className="bg-navy hover:bg-navy/90 px-8 py-6"
                disabled={symptomMutation.isPending || selectedSymptoms.length === 0}
              >
                {symptomMutation.isPending ? "Saving..." : "Save Symptoms"}
              </Button>
            </div>
          </div>
        )}
      </div>
    </section>
  );
};

export default LogSymptom;
