import Hero from "@/components/home/Hero";
import Features from "@/components/home/Features";
import Testimonials from "@/components/home/Testimonials";
import CallToAction from "@/components/home/CallToAction";

const Home = () => {
  return (
    <div className="space-y-0">
      <Hero />
      <Features />
      <Testimonials />
      <CallToAction />
    </div>
  );
};

export default Home;
