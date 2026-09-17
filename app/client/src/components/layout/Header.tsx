import { useState } from "react";
import { Link, useLocation } from "wouter";
import { Menu, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/hooks/useAuth";


const Header = () => {
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const [location] = useLocation();
  const { user } = useAuth();

  const navItems = [
    { href: "/dashboard", label: "Dashboard" },
    { href: "/log-meal", label: "Log Meal" },
    { href: "/log-symptom", label: "Log Symptoms" },
    { href: "/insights", label: "Insights" },
    { href: "/history", label: "History" },
  ];

  const toggleMenu = () => {
    setIsMenuOpen(!isMenuOpen);
  };

  return (
    <header className="bg-white shadow-sm">
      <div className="container mx-auto px-4 py-2 flex justify-between items-center">
        <div className="flex items-center space-x-2">
          <Link href="/" className="flex items-center">
            <img 
              src="/tastetrace-logo.png?v=2" 
              alt="TasteTrace Logo" 
              className="h-10 w-auto" 
            />
          </Link>
        </div>
        <nav className="flex items-center space-x-4">
          <Button
            variant="ghost"
            size="icon"
            className="md:hidden text-navy"
            onClick={toggleMenu}
            aria-label="Toggle menu"
          >
            {isMenuOpen ? <X size={24} /> : <Menu size={24} />}
          </Button>
          <ul className="hidden md:flex space-x-8">
            {navItems.map((item) => (
              <li key={item.href}>
                <Link href={item.href}>
                  <a
                    className={`text-navy font-medium hover:text-blue-500 transition ${
                      location === item.href ? "text-blue-500" : ""
                    }`}
                  >
                    {item.label}
                  </a>
                </Link>
              </li>
            ))}
          </ul>
          
          {/* User info and logout */}
          <div className="hidden md:flex items-center space-x-4">
            {user && (
              <div className="flex items-center space-x-2">
                {(user as any).profileImageUrl && (
                  <img
                    src={(user as any).profileImageUrl}
                    alt="Profile"
                    className="w-8 h-8 rounded-full object-cover"
                  />
                )}
                <span className="text-sm text-gray-600">
                  {(user as any).firstName} {(user as any).lastName}
                </span>
              </div>
            )}
            <Button
              onClick={async () => {
                try {
                  await fetch("/api/logout", { method: "POST" });
                  window.location.reload();
                } catch (error) {
                  console.error("Logout failed:", error);
                }
              }}
              variant="outline"
              className="border-navy text-navy hover:bg-navy hover:text-white"
            >
              Sign Out
            </Button>
          </div>
        </nav>
      </div>
      {/* Mobile menu */}
      {isMenuOpen && (
        <div className="md:hidden">
          <ul className="bg-white px-4 py-2 shadow-md">
            {navItems.map((item) => (
              <li key={item.href} className="py-2">
                <Link href={item.href}>
                  <a
                    className={`block text-navy font-medium ${
                      location === item.href ? "text-blue-500" : ""
                    }`}
                    onClick={() => setIsMenuOpen(false)}
                  >
                    {item.label}
                  </a>
                </Link>
              </li>
            ))}
            <li className="py-2 border-t">
              <Button
                onClick={async () => {
                  try {
                    await fetch("/api/logout", { method: "POST" });
                    window.location.reload();
                  } catch (error) {
                    console.error("Logout failed:", error);
                  }
                }}
                variant="outline"
                className="w-full border-navy text-navy hover:bg-navy hover:text-white"
              >
                Sign Out
              </Button>
            </li>
          </ul>
        </div>
      )}
    </header>
  );
};

export default Header;
