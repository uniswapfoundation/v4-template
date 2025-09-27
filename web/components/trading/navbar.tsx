"use client";
import { Button } from "@/components/ui/button";
import MonkeyIcon from "@/components/icons/monkey";
import GearIcon from "@/components/icons/gear";
import { cn } from "@/lib/core";
import { WalletConnectButton } from "./wallet-connect-button";
import { useState } from "react";
import { Menu, X } from "lucide-react";

const navItems = [];

export default function TradingNavbar() {
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);

  return (
    <nav className="w-full bg-background border-b border-border px-2 sm:px-4 py-3">
      <div className="flex items-center justify-between">
        {/* Left: Logo and Navigation */}
        <div className="flex items-center gap-4 lg:gap-8">
          {/* Logo */}
          <div className="flex items-center gap-2">
            <div className="flex items-center gap-2">
              <MonkeyIcon className="size-5 sm:size-6 text-primary" />
              <span className="text-lg sm:text-xl font-display">UNIPERP</span>
            </div>
          </div>

          {/* Navigation Items - Desktop */}
          <div className="hidden lg:flex items-center gap-6">
            {navItems.map((item) => (
              <button
                key={item.name}
                className={cn(
                  "text-sm font-medium transition-colors hover:text-foreground",
                  item.active ? "text-foreground" : "text-muted-foreground"
                )}
              >
                {item.name}
              </button>
            ))}
          </div>

          <Button
            variant="ghost"
            size="icon"
            className="lg:hidden"
            onClick={() => setIsMobileMenuOpen(!isMobileMenuOpen)}
          >
            {isMobileMenuOpen ? (
              <X className="size-4" />
            ) : (
              <Menu className="size-4" />
            )}
          </Button>
        </div>

        {/* Right: Connect Button and Settings */}
        <div className="flex items-center gap-2 sm:gap-3">
          <WalletConnectButton />
          <Button variant="ghost" size="icon" className="hidden sm:flex">
            <GearIcon className="size-4" />
          </Button>
        </div>
      </div>

      {isMobileMenuOpen && (
        <div className="lg:hidden mt-4 pb-4 border-t border-border">
          <div className="flex flex-col gap-2 pt-4">
            {navItems.map((item) => (
              <button
                key={item.name}
                className={cn(
                  "text-left px-2 py-2 text-sm font-medium transition-colors hover:text-foreground hover:bg-accent/50 rounded",
                  item.active
                    ? "text-foreground bg-accent/30"
                    : "text-muted-foreground"
                )}
                onClick={() => setIsMobileMenuOpen(false)}
              >
                {item.name}
              </button>
            ))}
          </div>
        </div>
      )}
    </nav>
  );
}
