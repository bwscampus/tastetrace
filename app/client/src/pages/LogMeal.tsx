import { useState, useEffect } from "react";
import { useQuery, useMutation } from "@tanstack/react-query";
import { queryClient, apiRequest } from "@/lib/queryClient";
import { useLocation } from "wouter";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/hooks/use-toast";
import { Switch } from "@/components/ui/switch";
import MealTile from "@/components/meal/MealTile";
import MealForm from "@/components/meal/MealForm";
import { commonMeals } from "@/lib/constants";
import { MealType } from "@shared/schema";

const LogMeal = () => {
  const [_, navigate] = useLocation();
  const [mealName, setMealName] = useState("");
  const [mealType, setMealType] = useState<MealType>(MealType.BREAKFAST);
  const [notes, setNotes] = useState("");
  const [ingredients, setIngredients] = useState("");
  const [saveAsPreset, setSaveAsPreset] = useState(false);
  const [selectedTiles, setSelectedTiles] = useState<string[]>([]);
  const [dietaryTags, setDietaryTags] = useState({
    containsGluten: false,
    containsDairy: false,
    containsGrains: false,
    containsSugar: false,
    containsNuts: false,
  });
  const [customPresets, setCustomPresets] = useState<string[]>(() => {
    const saved = localStorage.getItem('customFoodPresets');
    return saved ? JSON.parse(saved) : [];
  });
  const [date, setDate] = useState<Date>(new Date());
  const [time, setTime] = useState(() => {
    const now = new Date();
    const hours = now.getHours().toString().padStart(2, "0");
    const minutes = now.getMinutes().toString().padStart(2, "0");
    return `${hours}:${minutes}`;
  });

  // Mutation for creating a meal
  const mealMutation = useMutation({
    mutationFn: (mealData: any) => {
      return apiRequest("POST", "/api/meals", mealData);
    },
    onSuccess: () => {
      // Invalidate and refetch
      queryClient.invalidateQueries({ queryKey: ["/api/meals"] });
      queryClient.invalidateQueries({ queryKey: ["/api/entries/recent"] });
      
      toast({
        title: "Meal saved successfully!",
        description: "Your meal has been logged.",
      });
      
      navigate("/dashboard");
    },
    onError: (error: any) => {
      toast({
        title: "Failed to save meal",
        description: error.message || "Please try again.",
        variant: "destructive",
      });
    },
  });

  const handleMealTileClick = (name: string) => {
    const isSelected = selectedTiles.includes(name);
    
    if (isSelected) {
      // Remove from selection
      const newSelection = selectedTiles.filter(tile => tile !== name);
      setSelectedTiles(newSelection);
      setMealName(newSelection.join(", "));
    } else {
      // Add to selection
      const newSelection = [...selectedTiles, name];
      setSelectedTiles(newSelection);
      setMealName(newSelection.join(", "));
    }
  };

  // Save custom presets to localStorage whenever they change
  useEffect(() => {
    localStorage.setItem('customFoodPresets', JSON.stringify(customPresets));
  }, [customPresets]);

  const handleCustomMealSubmit = () => {
    if (!mealName.trim()) {
      toast({
        title: "Meal name required",
        description: "Please enter what you ate or select from the options above.",
        variant: "destructive",
      });
      return;
    }
    
    // Save as preset if the option is selected
    if (saveAsPreset && !customPresets.includes(mealName)) {
      setCustomPresets([...customPresets, mealName]);
      toast({
        title: "Preset saved",
        description: `"${mealName}" added to your custom meal presets.`,
      });
    }
    
    // Include dietary tags in notes if any are selected
    let processedNotes = notes;
    const activeTags = [];
    
    if (dietaryTags.containsGluten) activeTags.push("Contains gluten");
    if (dietaryTags.containsDairy) activeTags.push("Contains dairy");
    if (dietaryTags.containsGrains) activeTags.push("Contains grains");
    if (dietaryTags.containsSugar) activeTags.push("Contains sugar");
    if (dietaryTags.containsNuts) activeTags.push("Contains nuts");
    
    if (activeTags.length > 0) {
      processedNotes = processedNotes 
        ? `${processedNotes}\n\nDietary tags: ${activeTags.join(", ")}`
        : `Dietary tags: ${activeTags.join(", ")}`;
    }
    
    // Extract ingredients from the notes if they exist
    const ingredientsArray = ingredients
      ? ingredients.split(',').map(item => item.trim()).filter(Boolean)
      : [];
    
    const mealData = {
      name: mealName,
      mealType,
      notes: processedNotes,
      ingredients: ingredientsArray,
      containsGluten: dietaryTags.containsGluten,
      containsDairy: dietaryTags.containsDairy,
      containsGrains: dietaryTags.containsGrains,
      containsSugar: dietaryTags.containsSugar,
      containsNuts: dietaryTags.containsNuts,
      isCustom: true,
      timestamp: createTimestampFromTimeString(time), // This should create a date with the selected time
    };
    
    mealMutation.mutate(mealData);
  };

  // Now using both date and time to create an accurate timestamp
  const createTimestampFromTimeString = (timeString: string) => {
    const [hours, minutes] = timeString.split(":").map(Number);
    
    // Create a new date object based on the selected date
    const timestamp = new Date(date);
    
    // Set the hours and minutes from the time input
    timestamp.setHours(hours, minutes, 0, 0);
    
    return timestamp.toISOString();
  };

  return (
    <section className="py-12 bg-white">
      <div className="container mx-auto px-4">
        <h1 className="text-2xl md:text-3xl font-bold text-navy mb-8">Log Your Meals</h1>
        
        <MealForm 
          mealType={mealType}
          setMealType={setMealType}
          time={time}
          setTime={setTime}
          date={date}
          setDate={setDate}
        />
        
        <div className="mb-6">
          <label className="block text-gray-700 font-medium mb-2">Common meals (tap to select multiple)</label>
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3">
            {commonMeals.map((meal) => (
              <MealTile 
                key={meal} 
                name={meal} 
                onClick={() => handleMealTileClick(meal)}
                isSelected={selectedTiles.includes(meal)}
              />
            ))}
          </div>
        </div>

        {customPresets.length > 0 && (
          <div className="mb-6">
            <label className="block text-gray-700 font-medium mb-2">Your saved meals</label>
            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3">
              {customPresets.map((meal) => (
                <MealTile 
                  key={meal} 
                  name={meal} 
                  onClick={() => handleMealTileClick(meal)}
                  isSelected={selectedTiles.includes(meal)}
                />
              ))}
            </div>
          </div>
        )}
        
        <div className="mb-6">
          <label htmlFor="custom-meal" className="block text-gray-700 font-medium mb-2">
            Or write what you ate
          </label>
          <div className="mb-2">
            <Input
              id="custom-meal"
              type="text"
              placeholder="E.g., Avocado toast with egg"
              value={mealName}
              onChange={(e) => setMealName(e.target.value)}
              className="w-full"
            />
          </div>
          <div className="flex items-center space-x-2 mb-2">
            <Switch
              id="save-preset"
              checked={saveAsPreset}
              onCheckedChange={setSaveAsPreset}
            />
            <label
              htmlFor="save-preset"
              className="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70"
            >
              Save as preset for future use
            </label>
          </div>
          <div className="text-sm text-blue-600 pb-2">
            <p className="mb-1">✓ For dishes with multiple ingredients (like smoothies or sandwiches), we recommend:</p>
            <ul className="list-disc pl-5 text-gray-600">
              <li>Be specific with ingredients in your meal name (e.g., "BLT Sandwich with mayo")</li>
              <li>Or list individual ingredients in notes below for better tracking</li>
            </ul>
          </div>
        </div>
        
        <div className="mb-6">
          <label htmlFor="meal-ingredients" className="block text-gray-700 font-medium mb-2">
            Ingredients
          </label>
          <div className="text-sm text-gray-500 mb-2">
            List ingredients separated by commas to identify specific triggers
          </div>
          <Textarea
            id="meal-ingredients"
            rows={2}
            placeholder="E.g., wheat bread, turkey, lettuce, tomato, mayo"
            value={ingredients}
            onChange={(e) => setIngredients(e.target.value)}
            className="w-full mb-4"
          />
          
          <label htmlFor="meal-notes" className="block text-gray-700 font-medium mb-2">
            Additional Notes
          </label>
          <Textarea
            id="meal-notes"
            rows={2}
            placeholder="Any additional details about the meal"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            className="w-full mb-2"
          />
          <div className="text-xs text-gray-500 mb-4">
            Breaking down your meal into specific ingredients helps identify exactly what might be causing symptoms
          </div>

          <div className="mt-4">
            <div className="text-sm font-medium text-gray-700 mb-2">Mark if the meal DOES contain:</div>
            <div className="grid grid-cols-2 sm:grid-cols-5 gap-2">
              <div className="flex items-center space-x-2">
                <Switch 
                  id="contains-gluten" 
                  checked={dietaryTags.containsGluten}
                  onCheckedChange={(checked) => setDietaryTags({...dietaryTags, containsGluten: checked})}
                />
                <label 
                  htmlFor="contains-gluten" 
                  className="text-sm font-medium leading-none cursor-pointer"
                >
                  Gluten
                </label>
              </div>
              <div className="flex items-center space-x-2">
                <Switch 
                  id="contains-dairy" 
                  checked={dietaryTags.containsDairy}
                  onCheckedChange={(checked) => setDietaryTags({...dietaryTags, containsDairy: checked})}
                />
                <label 
                  htmlFor="contains-dairy" 
                  className="text-sm font-medium leading-none cursor-pointer"
                >
                  Dairy
                </label>
              </div>
              <div className="flex items-center space-x-2">
                <Switch 
                  id="contains-grains" 
                  checked={dietaryTags.containsGrains}
                  onCheckedChange={(checked) => setDietaryTags({...dietaryTags, containsGrains: checked})}
                />
                <label 
                  htmlFor="contains-grains" 
                  className="text-sm font-medium leading-none cursor-pointer"
                >
                  Grains
                </label>
              </div>
              <div className="flex items-center space-x-2">
                <Switch 
                  id="contains-sugar" 
                  checked={dietaryTags.containsSugar}
                  onCheckedChange={(checked) => setDietaryTags({...dietaryTags, containsSugar: checked})}
                />
                <label 
                  htmlFor="contains-sugar" 
                  className="text-sm font-medium leading-none cursor-pointer"
                >
                  Sugar
                </label>
              </div>
              <div className="flex items-center space-x-2">
                <Switch 
                  id="contains-nuts" 
                  checked={dietaryTags.containsNuts}
                  onCheckedChange={(checked) => setDietaryTags({...dietaryTags, containsNuts: checked})}
                />
                <label 
                  htmlFor="contains-nuts" 
                  className="text-sm font-medium leading-none cursor-pointer"
                >
                  Nuts
                </label>
              </div>
            </div>
          </div>
        </div>
        
        <div className="flex justify-center">
          <Button 
            onClick={handleCustomMealSubmit}
            className="bg-navy hover:bg-navy/90 px-8 py-6 w-full md:w-2/3 text-lg"
            disabled={mealMutation.isPending || !mealName.trim()}
          >
            {mealMutation.isPending ? "Saving..." : (
              <div className="flex items-center justify-center">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6 mr-2" viewBox="0 0 20 20" fill="currentColor">
                  <path fillRule="evenodd" d="M10 5a1 1 0 011 1v3h3a1 1 0 110 2h-3v3a1 1 0 11-2 0v-3H6a1 1 0 110-2h3V6a1 1 0 011-1z" clipRule="evenodd" />
                </svg>
                {mealName.trim() ? `Save "${mealName}"` : "Save Meal"} 
              </div>
            )}
          </Button>
        </div>
      </div>
    </section>
  );
};

export default LogMeal;
