import { Star } from "lucide-react";

const Testimonials = () => {
  return (
    <section className="py-12 bg-white">
      <div className="container mx-auto px-4">
        <h2 className="text-2xl md:text-3xl font-bold text-navy text-center mb-12">
          What Users Say
        </h2>
        
        <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
          {/* Testimonial 1 */}
          <div className="bg-light-blue p-6 rounded-xl shadow-sm">
            <div className="flex items-center mb-4">
              <div className="text-yellow-400 flex">
                <Star className="fill-current" size={20} />
                <Star className="fill-current" size={20} />
                <Star className="fill-current" size={20} />
                <Star className="fill-current" size={20} />
                <Star className="fill-current" size={20} />
              </div>
            </div>
            <p className="text-gray-600 mb-4">
              "After months of unexplained migraines, TasteTrace helped me identify that aged cheeses were the trigger. The simple logging made all the difference!"
            </p>
            <div className="flex items-center">
              <div className="w-10 h-10 bg-blue-500 rounded-full flex items-center justify-center text-white font-medium">
                JD
              </div>
              <div className="ml-3">
                <p className="font-medium">Jamie D.</p>
                <p className="text-gray-500 text-sm">Migraine sufferer</p>
              </div>
            </div>
          </div>
          
          {/* Testimonial 2 */}
          <div className="bg-light-blue p-6 rounded-xl shadow-sm">
            <div className="flex items-center mb-4">
              <div className="text-yellow-400 flex">
                <Star className="fill-current" size={20} />
                <Star className="fill-current" size={20} />
                <Star className="fill-current" size={20} />
                <Star className="fill-current" size={20} />
                <Star className="fill-current" size={20} />
              </div>
            </div>
            <p className="text-gray-600 mb-4">
              "I was shocked to discover my fatigue was linked to gluten. The app's patterns showed a clear connection I never noticed before. Life-changing!"
            </p>
            <div className="flex items-center">
              <div className="w-10 h-10 bg-navy rounded-full flex items-center justify-center text-white font-medium">
                SM
              </div>
              <div className="ml-3">
                <p className="font-medium">Sarah M.</p>
                <p className="text-gray-500 text-sm">Energy seeker</p>
              </div>
            </div>
          </div>
          
          {/* Testimonial 3 */}
          <div className="bg-light-blue p-6 rounded-xl shadow-sm">
            <div className="flex items-center mb-4">
              <div className="text-yellow-400 flex">
                <Star className="fill-current" size={20} />
                <Star className="fill-current" size={20} />
                <Star className="fill-current" size={20} />
                <Star className="fill-current" size={20} />
                <Star className="fill-current" size={20} />
              </div>
            </div>
            <p className="text-gray-600 mb-4">
              "As a parent with a child who has mysterious stomach issues, this app has been invaluable. We finally figured out dairy was causing problems. So simple to use!"
            </p>
            <div className="flex items-center">
              <div className="w-10 h-10 bg-blue-500 rounded-full flex items-center justify-center text-white font-medium">
                RB
              </div>
              <div className="ml-3">
                <p className="font-medium">Robert B.</p>
                <p className="text-gray-500 text-sm">Parent</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};

export default Testimonials;
