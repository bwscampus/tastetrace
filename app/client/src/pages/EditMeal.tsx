import { useEffect, useState } from "react";
import { useLocation } from "wouter";
import { useQuery, useMutation } from "@tanstack/react-query";
import { useForm } from "react-hook-form";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Checkbox } from "@/components/ui/checkbox";
import MealForm from "@/components/meal/MealForm";
import { apiRequest, queryClient } from "@/lib/queryClient";
import { toast } from "@/hooks/use-toast";
import { MealType } from "@shared/schema";
import { Label } from "@/components/ui/label";
import { ChevronLeft } from "lucide-react";

interface MealFormData {
  name: string;
  mealType: MealType;
  notes: string;
  ingredients: string;
  containsGluten: boolean;
  containsDairy: boolean;
  containsGrains: boolean;
  containsSugar: boolean;
  containsNuts: boolean;
}

const EditMeal = () => {
  const [, setLocation] = useLocation();
  const [time, setTime] = useState<string>("");
  const [date, setDate] = useState<Date>(new Date());
  const [mealType, setMealType] = useState<MealType>(MealType.BREAKFAST);
  const [isLoading, setIsLoading] = useState(true);
  const [mealId, setMealId] = useState<number | null>(null);

  const { register, handleSubmit, setValue, formState: { errors } } = useForm<MealFormData>({
    defaultValues: {
      name: "",
      mealType: MealType.BREAKFAST,
      notes: "",
      ingredients: "",
      containsGluten: false,
      containsDairy: false,
      containsGrains: false,
      containsSugar: false,
      containsNuts: false,
    },
  });

  // Get meal ID from URL path
  useEffect(() => {
    const pathParts = window.location.pathname.split('/');
    const id = parseInt(pathParts[pathParts.length - 1]);
    if (!isNaN(id)) {
      setMealId(id);
    }
  }, []);

  // Load meal data from sessionStorage or API
  useEffect(() => {
    try {
      const savedEntry = sessionStorage.getItem('editEntry');
      if (savedEntry) {
        const entry = JSON.parse(savedEntry);
        if (entry.type === 'meal') {
          const timeStr = new Date(entry.timestamp).toTimeString().slice(0, 5);
          setTime(timeStr);
          setMealType(entry.mealType as MealType);
          
          // Set form values
          setValue("name", entry.name);
          setValue("mealType", entry.mealType);
          setValue("notes", entry.notes || "");
          setValue("ingredients", entry.ingredients ? entry.ingredients.join(", ") : "");
          setValue("containsGluten", entry.containsGluten || false);
          setValue("containsDairy", entry.containsDairy || false);
          setValue("containsGrains", entry.containsGrains || false);
          setValue("containsSugar", entry.containsSugar || false);
          setValue("containsNuts", entry.containsNuts || false);
          
          setIsLoading(false);
          sessionStorage.removeItem('editEntry'); // Clear after use
        }
      }
    } catch (error) {
      console.error("Error loading meal data:", error);
    }
  }, [setValue]);

  // Fetch meal data from API if not in sessionStorage
  const { data: mealData } = useQuery({
    queryKey: ["/api/meals", mealId],
    enabled: !!(mealId && isLoading),
  });

  // Handle meal data when it's loaded
  useEffect(() => {
    if (mealData && isLoading) {
      try {
        const mealDate = new Date(mealData.timestamp);
        const timeStr = mealDate.toTimeString().slice(0, 5);
        setTime(timeStr);
        setDate(mealDate);
        setMealType(mealData.mealType as MealType);
        
        // Set form values
        setValue("name", mealData.name);
        setValue("mealType", mealData.mealType);
        setValue("notes", mealData.notes || "");
        setValue("ingredients", mealData.ingredients ? mealData.ingredients.join(", ") : "");
        setValue("containsGluten", mealData.containsGluten || false);
        setValue("containsDairy", mealData.containsDairy || false);
        setValue("containsGrains", mealData.containsGrains || false);
        setValue("containsSugar", mealData.containsSugar || false);
        setValue("containsNuts", mealData.containsNuts || false);
        
        setIsLoading(false);
      } catch (error) {
        console.error("Error processing meal data:", error);
      }
    }
  }, [mealData, isLoading, setValue]);

  const updateMealMutation = useMutation({
    mutationFn: (data: any) => {
      return apiRequest("PUT", `/api/meals/${mealId}`, data);
    },
    onSuccess: () => {
      toast({
        title: "Meal updated",
        description: "Your meal has been successfully updated",
      });
      queryClient.invalidateQueries({ queryKey: ["/api/entries/recent"] });
      queryClient.invalidateQueries({ queryKey: ["/api/correlations"] });
      setLocation("/dashboard");
    },
    onError: () => {
      toast({
        title: "Error updating meal",
        description: "There was a problem updating your meal",
        variant: "destructive",
      });
    },
  });

  const onSubmit = (data: MealFormData) => {
    const [hours, minutes] = time.split(":");
    
    // Use the selected date and set the hours and minutes
    const mealDate = new Date(date);
    mealDate.setHours(parseInt(hours), parseInt(minutes), 0, 0);
    
    const ingredientsArray = data.ingredients
      ? data.ingredients.split(",").map(item => item.trim()).filter(Boolean)
      : [];
    
    updateMealMutation.mutate({
      name: data.name,
      mealType: mealType,
      notes: data.notes,
      timestamp: mealDate.toISOString(),
      ingredients: ingredientsArray,
      containsGluten: data.containsGluten,
      containsDairy: data.containsDairy,
      containsGrains: data.containsGrains,
      containsSugar: data.containsSugar,
      containsNuts: data.containsNuts,
    });
  };

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
          <h1 className="text-2xl md:text-3xl font-bold text-navy mb-6">Edit Meal</h1>
          
          <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
            <MealForm 
              mealType={mealType} 
              setMealType={setMealType} 
              time={time} 
              setTime={setTime}
              date={date}
              setDate={setDate}
            />
            
            <div className="space-y-3">
              <Label htmlFor="name">Meal Name</Label>
              <Input
                id="name"
                placeholder="What did you eat?"
                {...register("name", { required: "Meal name is required" })}
                className="w-full"
              />
              {errors.name && (
                <p className="text-red-500 text-sm">{errors.name.message}</p>
              )}
            </div>
            
            <div className="space-y-3">
              <Label htmlFor="ingredients">Ingredients (comma separated)</Label>
              <Textarea
                id="ingredients"
                placeholder="List ingredients separated by commas"
                {...register("ingredients")}
                className="w-full"
              />
            </div>
            
            <div className="space-y-3">
              <Label>Mark if the meal DOES contain:</Label>
              <div className="grid grid-cols-2 sm:grid-cols-5 gap-4">
                <div className="flex items-center space-x-2">
                  <Checkbox 
                    id="containsGluten" 
                    {...register("containsGluten")} 
                  />
                  <label
                    htmlFor="containsGluten"
                    className="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70"
                  >
                    Contains gluten
                  </label>
                </div>
                <div className="flex items-center space-x-2">
                  <Checkbox 
                    id="containsDairy" 
                    {...register("containsDairy")} 
                  />
                  <label
                    htmlFor="containsDairy"
                    className="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70"
                  >
                    Contains dairy
                  </label>
                </div>
                <div className="flex items-center space-x-2">
                  <Checkbox 
                    id="containsGrains" 
                    {...register("containsGrains")} 
                  />
                  <label
                    htmlFor="containsGrains"
                    className="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70"
                  >
                    Contains grains
                  </label>
                </div>
                <div className="flex items-center space-x-2">
                  <Checkbox 
                    id="containsSugar" 
                    {...register("containsSugar")} 
                  />
                  <label
                    htmlFor="containsSugar"
                    className="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70"
                  >
                    Contains sugar
                  </label>
                </div>
                <div className="flex items-center space-x-2">
                  <Checkbox 
                    id="containsNuts" 
                    {...register("containsNuts")} 
                  />
                  <label
                    htmlFor="containsNuts"
                    className="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70"
                  >
                    Contains nuts
                  </label>
                </div>
              </div>
            </div>
            
            <div className="space-y-3">
              <Label htmlFor="notes">Notes</Label>
              <Textarea
                id="notes"
                placeholder="Any additional notes about this meal"
                {...register("notes")}
                className="w-full"
              />
            </div>
            
            <Button 
              type="submit" 
              className="w-full bg-navy hover:bg-navy/90"
              disabled={updateMealMutation.isPending}
            >
              {updateMealMutation.isPending ? "Updating..." : "Update Meal"}
            </Button>
          </form>
        </div>
      </div>
    </div>
  );
};

export default EditMeal;