import Hero from "@/components/home/Hero";
import Features from "@/components/home/Features";
import CallToAction from "@/components/home/CallToAction";

const Home = () => {
  return (
    <div className="space-y-0">
      <Hero />
      <Features />
      <CallToAction />
    </div>
  );
};

export default Home;
