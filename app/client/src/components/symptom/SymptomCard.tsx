import { useState } from "react";
import { Checkbox } from "@/components/ui/checkbox";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { SymptomSeverity } from "@shared/schema";
import { bowelMovementTypes } from "@/lib/constants";

interface SymptomCardProps {
  name: string;
  isChecked: boolean;
  severity: SymptomSeverity;
  onToggle: (checked: boolean, specificType?: string) => void;
  onSeverityChange: (severity: SymptomSeverity) => void;
}

const SymptomCard = ({
  name,
  isChecked,
  severity,
  onToggle,
  onSeverityChange,
}: SymptomCardProps) => {
  const [selectedBowelType, setSelectedBowelType] = useState<string>("");
  const isAbnormalBowelMovements = name === "Abnormal bowel movements";

  const handleToggle = (checked: boolean) => {
    if (isAbnormalBowelMovements && checked && !selectedBowelType) {
      // Don't toggle on if no bowel movement type is selected
      return;
    }
    onToggle(checked, isAbnormalBowelMovements ? selectedBowelType : undefined);
  };

  const handleBowelTypeChange = (type: string) => {
    setSelectedBowelType(type);
    if (!isChecked) {
      onToggle(true, type);
    } else {
      onToggle(true, type); // Update with new type
    }
  };

  return (
    <div 
      className={`border rounded-lg p-4 hover:border-blue-500 cursor-pointer ${isChecked ? 'border-blue-500' : 'border-gray-300'}`}
      onClick={() => !isAbnormalBowelMovements && handleToggle(!isChecked)}
    >
      <div className="flex items-center">
        <Checkbox
          id={`symptom-${name.toLowerCase().replace(/\s+/g, '-')}`}
          checked={isChecked}
          onCheckedChange={(checked) => handleToggle(!!checked)}
          className="mr-3"
          onClick={(e) => e.stopPropagation()} // Prevent double toggle when clicking directly on checkbox
        />
        <span className={`${!isAbnormalBowelMovements ? 'cursor-pointer' : ''}`}>
          {name}
        </span>
      </div>
      
      {/* Special handling for Abnormal bowel movements */}
      {isAbnormalBowelMovements && (
        <div className="mt-2">
          <Select
            value={selectedBowelType}
            onValueChange={handleBowelTypeChange}
          >
            <SelectTrigger className="w-full p-2 text-sm border border-gray-200 rounded">
              <SelectValue placeholder="Select type" />
            </SelectTrigger>
            <SelectContent>
              {bowelMovementTypes.map((type) => (
                <SelectItem key={type} value={type}>
                  {type}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      )}
      
      {isChecked && (
        <div className="mt-2">
          <Select
            value={severity}
            onValueChange={(value) => onSeverityChange(value as SymptomSeverity)}
          >
            <SelectTrigger className="w-full p-2 text-sm border border-gray-200 rounded">
              <SelectValue placeholder="Select severity" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={SymptomSeverity.MILD}>Mild</SelectItem>
              <SelectItem value={SymptomSeverity.MODERATE}>Moderate</SelectItem>
              <SelectItem value={SymptomSeverity.SEVERE}>Severe</SelectItem>
            </SelectContent>
          </Select>
        </div>
      )}
    </div>
  );
};

export default SymptomCard;
