"use client";
import { useState, useEffect } from "react";
import type React from "react";
import { motion, AnimatePresence } from "framer-motion";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Search, Star } from "lucide-react";

interface MarketSelectionDropdownProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSelectMarket: (market: string, chartType: "spot" | "perp") => void;
  currentMarket: string;
  currentChartType: "spot" | "perp";
  triggerRef?: React.RefObject<HTMLElement>;
}

import { MarketList } from "@/data/market-list";

// Get market data for all available markets
function useMarketsData(selectedCategory: string) {
  // Mock data for now - just return the markets with basic info
  const markets = MarketList.map((spot) => ({
    symbol: spot.symbol,
    price: "0.00",
    change: "0.00%",
    volume: "0M",
    isNegative: false,
    leverage: selectedCategory,
  }));

  return { markets, isLoading: false };
}

const categories = ["Perp", "Spot"];

export default function MarketSelectionDropdown({
  open,
  onOpenChange,
  onSelectMarket,
  currentMarket,
  currentChartType,
  triggerRef,
}: MarketSelectionDropdownProps) {
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedCategory, setSelectedCategory] = useState(
    currentChartType === "perp" ? "Perp" : "Spot"
  );

  // Update selectedCategory when currentChartType changes
  useEffect(() => {
    setSelectedCategory(currentChartType === "perp" ? "Perp" : "Spot");
  }, [currentChartType]);

  const { markets, isLoading } = useMarketsData(selectedCategory);

  const filteredMarkets = markets.filter((market) =>
    market.symbol.toLowerCase().includes(searchQuery.toLowerCase())
  );

  return (
    <AnimatePresence>
      {open && (
        <>
          <motion.div
            className="fixed inset-0 z-40"
            onClick={() => onOpenChange(false)}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.15 }}
          />

          <motion.div
            className="absolute top-full left-0 mt-2 w-full max-w-[1200px] min-w-[400px] bg-background border rounded-lg shadow-lg z-50 max-h-[500px] overflow-hidden"
            initial={{ opacity: 0, y: -10, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -10, scale: 0.95 }}
            transition={{
              duration: 0.2,
              ease: [0.16, 1, 0.3, 1],
            }}
          >
            <div className="p-2 sm:p-4 space-y-2 sm:space-y-4">
              <div className="flex items-center justify-between">
                <h3 className="text-base sm:text-lg font-semibold">
                  Select Market
                </h3>
              </div>

              {/* Search */}
              <div className="relative">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-muted-foreground h-4 w-4" />
                <Input
                  placeholder="Search"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="pl-10"
                />
              </div>

              {/* Categories */}
              <div className="flex flex-wrap gap-2">
                {categories.map((category) => (
                  <Button
                    key={category}
                    variant={
                      selectedCategory === category ? "default" : "ghost"
                    }
                    size="sm"
                    onClick={() => {
                      console.log("Category clicked:", category);
                      setSelectedCategory(category);
                      // Immediately update chart type when toggle is clicked
                      const chartType = category === "Perp" ? "perp" : "spot";
                      onSelectMarket(currentMarket, chartType);
                    }}
                    className="text-xs"
                  >
                    {category}
                  </Button>
                ))}
              </div>

              {/* Market List */}
              <div className="overflow-y-auto max-h-80">
                <div className="hidden lg:grid grid-cols-6 gap-4 text-xs text-muted-foreground mb-2 px-2">
                  <div>Symbol</div>
                  <div>Last Price</div>
                  <div>24hr Change</div>
                  <div>8hr Funding</div>
                  <div>Volume</div>
                  <div>Open Interest</div>
                </div>

                {isLoading ? (
                  <div className="flex items-center justify-center py-8">
                    <div className="text-sm text-muted-foreground">
                      Loading markets...
                    </div>
                  </div>
                ) : (
                  <div className="space-y-1">
                    {filteredMarkets.map((market) => (
                      <div
                        key={market.symbol}
                        className="lg:grid lg:grid-cols-6 lg:gap-16 p-2 hover:bg-accent/50 rounded cursor-pointer transition-colors"
                        onClick={() => {
                          const chartType =
                            selectedCategory === "Perp" ? "perp" : "spot";
                          console.log(
                            "Market selected:",
                            market.symbol,
                            "Chart type:",
                            chartType
                          );
                          onSelectMarket(market.symbol, chartType);
                          onOpenChange(false);
                        }}
                      >
                        <div className="lg:hidden space-y-2">
                          <div className="flex items-center justify-between">
                            <div className="flex items-center gap-2">
                              <Star className="h-3 w-3 text-muted-foreground" />
                              <span className="font-mono text-sm font-medium">
                                {market.symbol}
                              </span>
                            </div>
                            <div className="font-mono text-sm font-medium">
                              {market.price}
                            </div>
                          </div>
                          <div className="flex items-center justify-between text-xs">
                            <div
                              className={`font-mono ${
                                market.isNegative
                                  ? "text-destructive"
                                  : "text-green-500"
                              }`}
                            >
                              {market.change}
                            </div>
                            <div className="font-mono text-muted-foreground">
                              Vol: ${market.volume}
                            </div>
                          </div>
                        </div>

                        <div className="hidden lg:contents">
                          <div className="flex items-center gap-2">
                            <Star className="h-3 w-3 text-muted-foreground" />
                            <span className="font-mono text-sm">
                              {market.symbol}
                            </span>
                          </div>
                          <div className="font-mono text-sm">
                            {market.price}
                          </div>
                          <div
                            className={`font-mono text-sm ${
                              market.isNegative
                                ? "text-destructive"
                                : "text-green-500"
                            }`}
                          >
                            {market.change}
                          </div>
                          <div className="font-mono text-sm">0.0100%</div>
                          <div className="font-mono text-sm">
                            ${market.volume}
                          </div>
                          <div className="font-mono text-sm">$650M</div>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}
