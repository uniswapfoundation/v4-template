import { useQueryClient } from "@tanstack/react-query";
import { useCallback } from "react";

export function usePortfolioRefresh() {
  const queryClient = useQueryClient();

  const refreshPortfolio = useCallback(async () => {
    console.log("🔄 Force refreshing portfolio data...");

    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ["positions-with-balance"] }),
      queryClient.invalidateQueries({ queryKey: ["real-positions"] }),
      queryClient.invalidateQueries({ queryKey: ["positions"] }),
      queryClient.invalidateQueries({ queryKey: ["margin-balance"] }),
    ]);

    // Force refetch the main positions query
    await queryClient.refetchQueries({ queryKey: ["positions-with-balance"] });

    console.log("✅ Portfolio data refreshed");
  }, [queryClient]);

  return { refreshPortfolio };
}
