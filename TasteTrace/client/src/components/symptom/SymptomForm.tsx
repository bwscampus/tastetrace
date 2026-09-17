import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

interface SymptomFormProps {
  time: string;
  setTime: (time: string) => void;
  day: string;
  setDay: (day: string) => void;
}

const SymptomForm = ({ time, setTime, day, setDay }: SymptomFormProps) => {
  return (
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
  );
};

export default SymptomForm;
