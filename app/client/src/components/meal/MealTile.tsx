import { Button } from "@/components/ui/button";

interface MealTileProps {
  name: string;
  onClick: () => void;
  isSelected?: boolean;
}

const MealTile = ({ name, onClick, isSelected = false }: MealTileProps) => {
  return (
    <Button
      variant="outline"
      className={`px-4 py-3 rounded-lg transition text-center ${
        isSelected 
          ? 'bg-navy text-white border-navy shadow-md' 
          : 'bg-light-blue text-navy hover:bg-blue-500 hover:text-white'
      }`}
      onClick={onClick}
    >
      {name}
    </Button>
  );
};

export default MealTile;
