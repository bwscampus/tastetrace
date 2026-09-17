import { Link } from "wouter";
import { Button } from "@/components/ui/button";

const CallToAction = () => {
  return (
    <section className="py-16 bg-navy text-white">
      <div className="container mx-auto px-4 text-center">
        <h2 className="text-2xl md:text-3xl font-bold mb-4">
          Start Your Food Sensitivity Journey Today
        </h2>
        <p className="text-blue-100 mb-8 max-w-2xl mx-auto">
          Feel better, faster - without complicated tests. TasteTrace helps you identify which foods may be triggering your symptoms, using just a few seconds a day.
        </p>
        <Button asChild className="bg-white text-navy hover:bg-blue-50 px-8 py-6">
          <Link href="/dashboard">Get Started for Free</Link>
        </Button>
      </div>
    </section>
  );
};

export default CallToAction;
