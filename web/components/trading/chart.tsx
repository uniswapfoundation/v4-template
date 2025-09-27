"use client";
import { useState, useRef, useEffect } from "react";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { ChevronUp } from "lucide-react";
import MarketSelectionDropdown from "./market-selection-modal";
import dynamic from "next/dynamic";
import { CandlestickSeries, createChart } from "lightweight-charts";
import { useMarket } from "@/context/market-context";
import { MarketList } from "@/data/market-list";
import { useSpotData } from "@/hooks/api/use-market-data";
import TimeframeSelector from "./timeframe-selector";

export default function TradingChart() {
  const chartRef = useRef<HTMLDivElement>(null);
  const marketButtonRef = useRef<HTMLButtonElement>(null);
  const chartInstanceRef = useRef<any>(null);
  const seriesRef = useRef<any>(null);

  const { selectedMarket, setSelectedMarket } = useMarket();
  const availableMarkets = MarketList;
  const [isMarketModalOpen, setIsMarketModalOpen] = useState(false);

  // Use spot data hook - gets market from context
  const { prices, candlestickData, loading, error } = useSpotData();

  // Initialize chart once
  useEffect(() => {
    if (!chartRef.current || chartInstanceRef.current) return;

    const chart = createChart(chartRef.current, {
      autoSize: true,
      layout: {
        background: { color: "oklch(0.2029 0.0037 345.62)" },
        textColor: "#ffffff",
      },
      grid: {
        vertLines: { color: "#444" },
        horzLines: { color: "#444" },
      },
    });

    const candlestickSeries = chart.addSeries(CandlestickSeries, {
      upColor: "#26a69a",
      downColor: "#ef5350",
      borderVisible: false,
      wickUpColor: "#26a69a",
      wickDownColor: "#ef5350",
    });

    // Set initial mock data to test chart visibility
    const mockData = [
      {
        time: Math.floor(Date.now() / 1000) - 3600,
        open: 100,
        high: 105,
        low: 95,
        close: 102,
      },
      {
        time: Math.floor(Date.now() / 1000) - 1800,
        open: 102,
        high: 108,
        low: 98,
        close: 106,
      },
      {
        time: Math.floor(Date.now() / 1000),
        open: 106,
        high: 110,
        low: 104,
        close: 108,
      },
    ];
    candlestickSeries.setData(mockData);

    chartInstanceRef.current = chart;
    seriesRef.current = candlestickSeries;

    return () => {
      if (chartInstanceRef.current) {
        chartInstanceRef.current.remove();
        chartInstanceRef.current = null;
        seriesRef.current = null;
      }
    };
  }, []);

  // Update chart with candlestick data
  useEffect(() => {
    if (candlestickData.length > 0 && seriesRef.current) {
      // Use pre-aggregated candlestick data from backend
      console.log("Setting candlestick data:", candlestickData);
      seriesRef.current.setData(candlestickData);
      chartInstanceRef.current.timeScale().fitContent();
    } else if (prices.length > 0 && seriesRef.current) {
      // Fallback to real-time price data if no candlestick data
      const fallbackData = prices.map((price) => ({
        time: Math.floor(price.timestamp / 1000), // Convert to seconds for Lightweight Charts
        open: price.price * 0.99,
        high: price.price * 1.01,
        low: price.price * 0.98,
        close: price.price,
      }));

      console.log("Setting fallback data:", fallbackData);
      seriesRef.current.setData(fallbackData);
      chartInstanceRef.current.timeScale().fitContent();
    }
  }, [candlestickData, prices]);

  const handleMarketSelect = (marketSymbol: string) => {
    const market = availableMarkets.find((m) => m.symbol === marketSymbol);
    if (market) {
      setSelectedMarket(market);
      setIsMarketModalOpen(false);
    }
  };

  return (
    <div className="h-full flex flex-col">
      <Card className="h-full flex flex-col">
        <CardHeader className="pb-3 px-3 sm:px-6 flex-shrink-0">
          <div className="flex flex-col gap-3">
            {/* Market selector and badge row */}
            <div className="flex flex-col sm:flex-row sm:items-center gap-3">
              <div className="relative flex items-center gap-2">
                <button
                  ref={marketButtonRef}
                  className="flex items-center gap-2 hover:bg-accent/50 rounded px-2 py-1 transition-colors"
                  onClick={() => setIsMarketModalOpen(!isMarketModalOpen)}
                >
                  <div className="w-5 h-5 sm:w-6 sm:h-6 bg-gradient-to-br from-blue-500 to-purple-600 rounded-full flex items-center justify-center">
                    <span className="text-white text-xs font-bold">H</span>
                  </div>
                  <span className="text-base sm:text-lg font-display">
                    {selectedMarket?.symbol || "Select Market"}
                  </span>
                  <div
                    className={`transition-transform duration-200 ${
                      isMarketModalOpen ? "rotate-180" : ""
                    }`}
                  >
                    <ChevronUp className="h-4 w-4 text-muted-foreground" />
                  </div>
                </button>
                <MarketSelectionDropdown
                  open={isMarketModalOpen}
                  onOpenChange={setIsMarketModalOpen}
                  onSelectMarket={handleMarketSelect}
                  currentMarket={selectedMarket?.symbol || ""}
                  triggerRef={marketButtonRef}
                />
              </div>
              <Badge variant="secondary" className="text-xs w-fit">
                Spot
              </Badge>
            </div>

            {/* Timeframe selector */}
            <div className="flex items-center gap-1 sm:gap-2 overflow-x-auto pb-1">
              <div className="flex items-center gap-1 sm:gap-2 min-w-max">
                <TimeframeSelector />
              </div>
            </div>
          </div>
        </CardHeader>
        <CardContent className="flex-1 p-0 relative">
          {loading && (
            <div className="absolute inset-0 flex items-center justify-center bg-background/80 z-10">
              <div className="text-sm text-muted-foreground">
                Loading chart data...
              </div>
            </div>
          )}
          {error && (
            <div className="absolute inset-0 flex items-center justify-center bg-background/80 z-10">
              <div className="text-sm text-destructive">Error: {error}</div>
            </div>
          )}
          <div ref={chartRef} className="w-full h-full"></div>
        </CardContent>
      </Card>
    </div>
  );
}
