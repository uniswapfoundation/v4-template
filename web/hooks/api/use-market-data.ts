import { useQuery } from "@tanstack/react-query";
import { useEffect, useState, useCallback } from "react";
import { useMarket } from "@/context/market-context";
import { useTimeframe } from "@/context/timeframe-context";
import { apiClient } from "@/lib/core";

// Types
export interface MarketDetails {
  id: string;
  name: string;
  symbol: string;
  description: string;
  currentPrice: number;
  priceChange24h: number;
  volume24h: number;
  marketCap: number;
  tradingHours: string;
  fees: {
    maker: number;
    taker: number;
  };
  limits: {
    minOrderSize: number;
    maxOrderSize: number;
  };
  lastUpdated: string;
}

export interface PriceData {
  id: string;
  price: number;
  timestamp: number;
  symbol?: string;
}

export interface CandlestickData {
  time: string;
  open: number;
  high: number;
  low: number;
  close: number;
  timestamp: number;
  volume?: number;
}

// Query Keys
export const marketDataKeys = {
  all: ["marketData"] as const,
  details: (marketId: string) =>
    [...marketDataKeys.all, "details", marketId] as const,
  multiple: (marketIds: string[]) =>
    [...marketDataKeys.all, "multiple", marketIds] as const,
  spot: (marketId: string, timeframe: string) =>
    [...marketDataKeys.all, "spot", marketId, timeframe] as const,
};

// Market Details Hooks
export function useMarketDetails(marketId: string) {
  return useQuery({
    queryKey: marketDataKeys.details(marketId),
    queryFn: () =>
      apiClient.get<MarketDetails>("/market-details", { marketId }),
    select: (response) => response.data,
    enabled: !!marketId,
    staleTime: 2 * 60 * 1000, // 2 minutes
    refetchInterval: 30 * 1000, // Refetch every 30 seconds for live data
    gcTime: 10 * 60 * 1000, // Keep in cache for 10 minutes
    refetchOnWindowFocus: false, // Don't refetch on window focus
    refetchOnMount: true, // Refetch when component mounts
    retry: 3, // Retry failed requests 3 times
    retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000), // Exponential backoff
  });
}

// Hook to get multiple market details
export function useMultipleMarketDetails(marketIds: string[]) {
  return useQuery({
    queryKey: marketDataKeys.multiple(marketIds),
    queryFn: async () => {
      const promises = marketIds.map((id) =>
        apiClient.get<MarketDetails>("/market-details", { marketId: id })
      );
      const responses = await Promise.all(promises);
      return responses.map((response) => response.data);
    },
    enabled: marketIds.length > 0,
    staleTime: 2 * 60 * 1000, // 2 minutes
    gcTime: 10 * 60 * 1000, // Keep in cache for 10 minutes
    refetchOnWindowFocus: false, // Don't refetch on window focus
    refetchOnMount: true, // Refetch when component mounts
    retry: 3, // Retry failed requests 3 times
    retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000), // Exponential backoff
  });
}

// Spot Data Hook (consolidated from use-spot.ts)
export function useSpotData() {
  const { selectedMarket } = useMarket();
  const { selectedTimeframe } = useTimeframe();
  const [prices, setPrices] = useState<PriceData[]>([]);
  const [candlestickData, setCandlestickData] = useState<CandlestickData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [eventSource, setEventSource] = useState<EventSource | null>(null);

  const startPriceStream = useCallback(async () => {
    // TODO: Comment out price feed for now
    console.log("Price stream disabled for debugging");
    setLoading(false);
    return;

    if (!selectedMarket?.id) return;

    console.log(
      "Starting price stream for market ID:",
      selectedMarket.id,
      "timeframe:",
      selectedTimeframe
    );

    try {
      // Create SSE connection to our backend API with timeframe
      const eventSource = new EventSource(
        `/api/spot-data?marketId=${selectedMarket.id}&timeframe=${selectedTimeframe}`
      );

      eventSource.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);

          // Skip ping messages
          if (data.type === "ping") return;

          console.log(
            "Received data for market:",
            selectedMarket.id,
            "timeframe:",
            selectedTimeframe,
            data
          );

          if (data.type === "historical") {
            // Historical aggregated data
            console.log("Received historical data:", data.data);
            setCandlestickData(data.data);
            setLoading(false);
          } else {
            // Real-time price data
            const priceData = data.map((price: any) => ({
              id: price.id,
              price: price.price,
              timestamp: price.timestamp || price.publishTime,
              symbol: selectedMarket.symbol,
            }));

            console.log("Received real-time data:", priceData);
            setPrices(priceData);
            setLoading(false);
          }
        } catch (err) {
          console.error("Error parsing SSE data:", err);
        }
      };

      eventSource.onerror = (err) => {
        console.error("SSE connection error:", err);
        setError("Connection error");
        setLoading(false);
      };

      setEventSource(eventSource);
    } catch (err) {
      console.error("Error starting price stream:", err);
      setError(
        err instanceof Error ? err.message : "Failed to start price stream"
      );
      setLoading(false);
    }
  }, [selectedMarket, selectedTimeframe]);

  const stopPriceStream = useCallback(() => {
    if (eventSource) {
      eventSource.close();
      setEventSource(null);
    }
  }, [eventSource]);

  // Fetch historical data for specific timeframe
  const fetchHistoricalData = useCallback(
    async (timeframe: string = selectedTimeframe, limit: number = 100) => {
      if (!selectedMarket?.id) return [];

      try {
        const response = await fetch("/api/spot-data", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            marketId: selectedMarket.id,
            timeframe,
            limit,
          }),
        });

        if (!response.ok) {
          throw new Error("Failed to fetch historical data");
        }

        const data = await response.json();
        return data.data;
      } catch (err) {
        console.error("Error fetching historical data:", err);
        return [];
      }
    },
    [selectedMarket, selectedTimeframe]
  );

  useEffect(() => {
    return () => {
      if (eventSource) {
        eventSource.close();
      }
    };
  }, [eventSource]);

  useEffect(() => {
    if (selectedMarket?.id) {
      // Close existing connection
      if (eventSource) {
        eventSource.close();
        setEventSource(null);
      }
      // Start new connection with current timeframe
      startPriceStream();
    }
  }, [selectedMarket, selectedTimeframe, startPriceStream]);

  return {
    prices,
    candlestickData,
    loading,
    error,
    startPriceStream,
    stopPriceStream,
    fetchHistoricalData,
    isStreaming: !!eventSource,
  };
}

// Combined hook for all market data operations
export function useMarketData() {
  const { selectedMarket } = useMarket();
  const marketDetails = useMarketDetails(selectedMarket?.id || "");
  const spotData = useSpotData();

  return {
    marketDetails: marketDetails.data,
    marketDetailsLoading: marketDetails.isLoading,
    marketDetailsError: marketDetails.error,
    ...spotData,
  };
}
