import { Button } from "@/components/ui/button";
import Hero from "@/components/home/Hero";
import Features from "@/components/home/Features";
import Testimonials from "@/components/home/Testimonials";
import CallToAction from "@/components/home/CallToAction";
import Footer from "@/components/layout/Footer";

const Landing = () => {
  return (
    <div className="min-h-screen bg-gradient-to-b from-light-blue to-white">
      <header className="bg-white shadow-sm">
        <div className="container mx-auto px-4 py-4 flex justify-between items-center">
          <div className="flex items-center">
            <h1 className="text-2xl font-bold text-navy">TasteTrace</h1>
          </div>
          <div className="flex items-center space-x-4">
            <Button
              onClick={() => window.location.href = "/api/login"}
              className="bg-navy hover:bg-navy/90 text-white"
            >
              Sign In with Replit
            </Button>
          </div>
        </div>
      </header>

      <main>
        <Hero />
        <Features />
        <Testimonials />
        <CallToAction />
      </main>

      <Footer />
    </div>
  );
};

export default Landing;