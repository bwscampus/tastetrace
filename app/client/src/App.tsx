import { Switch, Route } from "wouter";
import { queryClient } from "./lib/queryClient";
import { QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";
import { useAuth } from "@/hooks/useAuth";
import NotFound from "@/pages/not-found";
import Header from "@/components/layout/Header";
import Footer from "@/components/layout/Footer";
import Dashboard from "@/pages/Dashboard";
import LogMeal from "@/pages/LogMeal";
import LogSymptom from "@/pages/LogSymptom";
import EditMeal from "@/pages/EditMeal";
import EditSymptom from "@/pages/EditSymptom";
import Insights from "@/pages/Insights";
import History from "@/pages/History";
import Home from "@/pages/Home";
import AuthPage from "@/pages/auth-page";

function Router() {
  const { isAuthenticated, isLoading } = useAuth();

  if (isLoading || !isAuthenticated) {
    return <AuthPage />;
  }

  return (
    <div className="flex flex-col min-h-screen space-y-0">
      <Header />
      <main className="flex-1 pt-0">
        <Switch>
          <Route path="/" component={Home} />
          <Route path="/dashboard" component={Dashboard} />
          <Route path="/log-meal" component={LogMeal} />
          <Route path="/log-symptom" component={LogSymptom} />
          <Route path="/edit-meal/:id" component={EditMeal} />
          <Route path="/edit-symptom/:id" component={EditSymptom} />
          <Route path="/insights" component={Insights} />
          <Route path="/history" component={History} />
          <Route component={NotFound} />
        </Switch>
      </main>
      <Footer />
    </div>
  );
}

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <TooltipProvider>
        <Toaster />
        <Router />
      </TooltipProvider>
    </QueryClientProvider>
  );
}

export default App;
