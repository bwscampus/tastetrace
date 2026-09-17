import { UtensilsCrossed, ClipboardList, LineChart } from "lucide-react";

const Features = () => {
  return (
    <section className="py-12 bg-light-blue" id="features">
      <div className="container mx-auto px-4">
        <h2 className="text-2xl md:text-3xl font-bold text-navy text-center mb-12">
          How TasteTrace Works
        </h2>
        
        <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
          {/* Feature 1 */}
          <div className="bg-white p-6 rounded-xl shadow-sm">
            <div className="w-12 h-12 bg-blue-100 rounded-full flex items-center justify-center mb-4">
              <UtensilsCrossed className="text-blue-500" size={24} />
            </div>
            <h3 className="text-xl font-semibold text-navy mb-2">Quick-Tap Meal Logging</h3>
            <p className="text-gray-600">
              Log meals in seconds using pre-saved meal tiles or custom entries, with auto-timestamping and optional notes/photos.
            </p>
          </div>
          
          {/* Feature 2 */}
          <div className="bg-white p-6 rounded-xl shadow-sm">
            <div className="w-12 h-12 bg-blue-100 rounded-full flex items-center justify-center mb-4">
              <ClipboardList className="text-blue-500" size={24} />
            </div>
            <h3 className="text-xl font-semibold text-navy mb-2">Smart Symptom Check-Ins</h3>
            <p className="text-gray-600">
              A single push notification asks about symptoms daily. The app links symptoms to meals from the past 12 hours.
            </p>
          </div>
          
          {/* Feature 3 */}
          <div className="bg-white p-6 rounded-xl shadow-sm">
            <div className="w-12 h-12 bg-blue-100 rounded-full flex items-center justify-center mb-4">
              <LineChart className="text-blue-500" size={24} />
            </div>
            <h3 className="text-xl font-semibold text-navy mb-2">Pattern Recognition</h3>
            <p className="text-gray-600">
              Discover connections between specific foods and your symptoms with our intelligent correlation engine.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
};

export default Features;
