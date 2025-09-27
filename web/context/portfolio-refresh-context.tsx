"use client";

import { createContext, useContext, useCallback } from "react";
import { useQueryClient } from "@tanstack/react-query";

interface PortfolioRefreshContextType {
  refreshPortfolio: () => void;
}

const PortfolioRefreshContext = createContext<
  PortfolioRefreshContextType | undefined
>(undefined);

export function PortfolioRefreshProvider({
  children,
}: {
  children: React.ReactNode;
}) {
  const queryClient = useQueryClient();

  const refreshPortfolio = useCallback(() => {
    console.log("🔄 Refreshing portfolio data...");
    // Invalidate all position-related queries
    queryClient.invalidateQueries({ queryKey: ["positions-with-balance"] });
    queryClient.invalidateQueries({ queryKey: ["real-positions"] });
    queryClient.invalidateQueries({ queryKey: ["positions"] });
    console.log("✅ Portfolio queries invalidated");
  }, [queryClient]);

  return (
    <PortfolioRefreshContext.Provider value={{ refreshPortfolio }}>
      {children}
    </PortfolioRefreshContext.Provider>
  );
}

export function usePortfolioRefresh() {
  const context = useContext(PortfolioRefreshContext);
  if (context === undefined) {
    throw new Error(
      "usePortfolioRefresh must be used within a PortfolioRefreshProvider"
    );
  }
  return context;
}
