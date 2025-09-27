"use client";

import { createContext, useState, useContext, ReactNode } from "react";
import { MarketList } from "@/data/market-list";

interface Market {
  id: string;
  symbol: string;
  name: string;
}

interface MarketContextType {
  selectedMarket: Market | null;
  setSelectedMarket: (market: Market | null) => void;
}

const MarketContext = createContext<MarketContextType | undefined>(undefined);

export const MarketProvider = ({ children }: { children: ReactNode }) => {
  const [selectedMarket, setSelectedMarket] = useState<Market | null>({
    id: MarketList[0].id,
    symbol: MarketList[0].symbol,
    name: MarketList[0].name,
  });

  return (
    <MarketContext.Provider
      value={{
        selectedMarket,
        setSelectedMarket,
      }}
    >
      {children}
    </MarketContext.Provider>
  );
};

export const useMarket = () => {
  const context = useContext(MarketContext);
  console.log("market context", context);
  if (context === undefined) {
    throw new Error("useMarket must be used within a MarketProvider");
  }
  return context;
};
