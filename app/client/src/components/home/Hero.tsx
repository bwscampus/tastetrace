import { Link } from "wouter";
import { Button } from "@/components/ui/button";


const Hero = () => {
  return (
    <section className="bg-white">
      <div className="container mx-auto px-4 -mt-2">
        <div className="flex flex-col md:flex-row items-center overflow-hidden gap-1">
          <div className="md:w-1/2 md:pr-8">
            <h1 className="text-3xl md:text-4xl font-bold text-navy mb-1">
              Connect Your Food to Symptoms, Effortlessly
            </h1>
            <p className="text-gray-600 mb-2">
              TasteTrace helps you discover links between what you eat and how you feel — without complicated inputs or behavior change.
            </p>
            <div className="flex flex-col sm:flex-row gap-2">
              <Button asChild className="bg-navy hover:bg-navy/90 px-4 py-2">
                <Link href="/dashboard">Get Started</Link>
              </Button>
              <Button asChild variant="outline" className="border-navy text-navy hover:bg-navy hover:text-white px-4 py-2">
                <Link href="#features">Learn More</Link>
              </Button>
            </div>
          </div>
          <div className="md:w-1/2 md:mt-0 flex justify-center items-center">
            <img 
              src="/tastetrace-logo.png?v=2" 
              alt="TasteTrace Logo" 
              className="w-full h-auto scale-110 md:scale-100" 
            />
          </div>
        </div>
      </div>
    </section>
  );
};

export default Hero;
