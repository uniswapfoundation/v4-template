"use client";
import { useState } from "react";
import type React from "react";
import { motion, AnimatePresence } from "framer-motion";

import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Search, Star } from "lucide-react";

interface MarketSelectionDropdownProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSelectMarket: (market: string) => void;
  currentMarket: string;
  triggerRef?: React.RefObject<HTMLElement>;
}

import { MarketList } from "@/data/market-list";
import { useMultipleMarketDetails } from "@/hooks/api";

// Get market data for all available markets
function useMarketsData() {
  const marketIds = MarketList.map((spot) => spot.symbol);
  const { data: marketsData, isLoading } = useMultipleMarketDetails(marketIds);

  const markets = MarketList.map((spot, index) => {
    const marketData = marketsData?.[index];

    if (!marketData) {
      return {
        symbol: spot.symbol,
        price: "0.00",
        change: "0.00%",
        volume: "0M",
        isNegative: false,
        leverage: "Spot",
      };
    }

    return {
      symbol: spot.symbol,
      price: marketData.currentPrice.toFixed(2),
      change: `${
        marketData.priceChange24h >= 0 ? "+" : ""
      }${marketData.priceChange24h.toFixed(2)}%`,
      volume: `${(marketData.volume24h / 1000000).toFixed(0)}M`,
      isNegative: marketData.priceChange24h < 0,
      leverage: "Spot",
    };
  });

  return { markets, isLoading };
}

const categories = ["Perp", "Spot"];

export default function MarketSelectionDropdown({
  open,
  onOpenChange,
  onSelectMarket,
  currentMarket,
  triggerRef,
}: MarketSelectionDropdownProps) {
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedCategory, setSelectedCategory] = useState("Perp");

  const { markets, isLoading } = useMarketsData();

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
            className="absolute top-full left-0 mt-2 w-full max-w-[800px] min-w-[320px] bg-background border rounded-lg shadow-lg z-50 max-h-[500px] overflow-hidden"
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
                    onClick={() => setSelectedCategory(category)}
                    className="text-xs"
                  >
                    {category}
                    {category === "Spot" && <span className="ml-1">🔗</span>}
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
                        className="lg:grid lg:grid-cols-6 lg:gap-4 p-2 hover:bg-accent/50 rounded cursor-pointer transition-colors"
                        onClick={() => {
                          onSelectMarket(market.symbol);
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
                              {market.leverage && (
                                <Badge
                                  variant="secondary"
                                  className="text-xs px-1 py-0"
                                >
                                  {market.leverage}
                                </Badge>
                              )}
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
                            {market.leverage && (
                              <Badge
                                variant="secondary"
                                className="text-xs px-1 py-0"
                              >
                                {market.leverage}
                              </Badge>
                            )}
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
