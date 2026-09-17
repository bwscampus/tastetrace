import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { MealType } from "@shared/schema";
import { Calendar } from "@/components/ui/calendar";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { CalendarIcon } from "lucide-react";
import { format } from "date-fns";

interface MealFormProps {
  mealType: MealType;
  setMealType: (type: MealType) => void;
  time: string;
  setTime: (time: string) => void;
  date: Date;
  setDate: (date: Date) => void;
}

const MealForm = ({ mealType, setMealType, time, setTime, date, setDate }: MealFormProps) => {
  return (
    <div className="mb-6">
      <label className="block text-gray-700 font-medium mb-2">When did you eat?</label>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="space-y-3">
          <div className="text-sm font-medium text-gray-500">Meal type:</div>
          <div className="flex flex-wrap gap-2">
            <Button 
              variant={mealType === MealType.BREAKFAST ? "default" : "outline"}
              className={mealType === MealType.BREAKFAST ? "bg-navy text-white" : "border-navy text-navy"}
              onClick={() => setMealType(MealType.BREAKFAST)}
            >
              Breakfast
            </Button>
            <Button 
              variant={mealType === MealType.LUNCH ? "default" : "outline"}
              className={mealType === MealType.LUNCH ? "bg-navy text-white" : "border-navy text-navy"}
              onClick={() => setMealType(MealType.LUNCH)}
            >
              Lunch
            </Button>
            <Button 
              variant={mealType === MealType.DINNER ? "default" : "outline"}
              className={mealType === MealType.DINNER ? "bg-navy text-white" : "border-navy text-navy"}
              onClick={() => setMealType(MealType.DINNER)}
            >
              Dinner
            </Button>
            <Button 
              variant={mealType === MealType.SNACK ? "default" : "outline"}
              className={mealType === MealType.SNACK ? "bg-navy text-white" : "border-navy text-navy"}
              onClick={() => setMealType(MealType.SNACK)}
            >
              Snack
            </Button>
          </div>
        </div>
        
        <div>
          <div className="text-sm font-medium text-gray-500 mb-3">Date and time (important for tracking):</div>
          <div className="flex items-center space-x-2">
            <Popover>
              <PopoverTrigger asChild>
                <Button
                  variant="outline"
                  className="w-[240px] justify-start text-left font-normal"
                >
                  <CalendarIcon className="mr-2 h-4 w-4" />
                  {date ? format(date, "PPP") : <span>Pick a date</span>}
                </Button>
              </PopoverTrigger>
              <PopoverContent className="w-auto p-0">
                <Calendar
                  mode="single"
                  selected={date}
                  onSelect={(date) => date && setDate(date)}
                  initialFocus
                />
              </PopoverContent>
            </Popover>
            
            <Input
              type="time"
              value={time}
              onChange={(e) => setTime(e.target.value)}
              className="w-[140px] border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
          <div className="mt-2 text-sm text-blue-600">
            Set the actual date and time you ate this meal for better correlations
          </div>
        </div>
      </div>
    </div>
  );
};

export default MealForm;
