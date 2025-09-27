"use client";

import { useState, useEffect } from "react";
import { useAccount } from "wagmi";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/core";
import { motion, AnimatePresence } from "framer-motion";
import { usePositionsWithBalance, Position } from "@/hooks/api/use-positions";
import { useQueryClient } from "@tanstack/react-query";
import { usePortfolioRefresh } from "@/hooks/use-portfolio-refresh";
import { portfolioEvents } from "@/lib/core";
import { PositionManagementModal } from "./position-management-modal";
// Note: Position actions are now available through usePositionManagement hook

export default function Portfolio() {
  const [activeTab, setActiveTab] = useState<"open" | "closed">("open");
  const [sideFilter, setSideFilter] = useState<"all" | "long" | "short">("all");
  const [searchTerm, setSearchTerm] = useState("");
  const [selectedPosition, setSelectedPosition] = useState<Position | null>(
    null
  );
  const [isModalOpen, setIsModalOpen] = useState(false);

  // Use enhanced position data with account balance
  const {
    data: positionsData,
    isLoading,
    isFetching,
    error,
    refetch,
  } = usePositionsWithBalance();
  const queryClient = useQueryClient();
  const { address } = useAccount();
  const { refreshPortfolio } = usePortfolioRefresh();

  // Auto-refresh portfolio when address changes
  useEffect(() => {
    if (address) {
      console.log("🔄 Address changed, refetching portfolio...");
      refetch();
    }
  }, [address, refetch]);

  // Listen for portfolio update events
  useEffect(() => {
    const handlePortfolioUpdate = () => {
      console.log("📢 Portfolio update event received, refetching...");
      refetch();
    };

    const unsubscribe = portfolioEvents.subscribe(handlePortfolioUpdate);

    return () => {
      unsubscribe();
    };
  }, [refetch]);

  // Listen for query invalidation and refetch
  useEffect(() => {
    const handleFocus = () => {
      console.log("🔄 Window focused, refetching portfolio...");
      refetch();
    };

    const handleVisibilityChange = () => {
      if (!document.hidden) {
        console.log("🔄 Page visible, refetching portfolio...");
        refetch();
      }
    };

    window.addEventListener("focus", handleFocus);
    document.addEventListener("visibilitychange", handleVisibilityChange);

    return () => {
      window.removeEventListener("focus", handleFocus);
      document.removeEventListener("visibilitychange", handleVisibilityChange);
    };
  }, [refetch]);

  // Position actions will be implemented later
  // const { closePosition, addMargin, removeMargin } = usePositionActions();

  // Filter positions based on validity
  const allPositions = positionsData?.positions || [];
  const openPositions = allPositions.filter(
    (position) =>
      position.margin > 0 &&
      position.sizeBase > 0 &&
      !isNaN(position.leverage) &&
      position.leverage > 0
  );
  const closedPositions = allPositions.filter(
    (position) =>
      position.margin === 0 ||
      position.sizeBase === 0 ||
      isNaN(position.leverage) ||
      position.leverage <= 0
  );

  // Combine positions and filter based on active tab
  const tabPositions = activeTab === "open" ? openPositions : closedPositions;

  const filteredPositions = tabPositions.filter((position) => {
    const matchesSide =
      sideFilter === "all" ||
      (sideFilter === "long" ? position.isLong : !position.isLong);
    const matchesSearch = "ETH/USDC"
      .toLowerCase()
      .includes(searchTerm.toLowerCase());
    return matchesSide && matchesSearch;
  });

  const totalPnl = filteredPositions.reduce(
    (sum, pos) => sum + pos.unrealizedPnL,
    0
  );
  const totalMargin = filteredPositions.reduce((sum, pos) => {
    return sum + pos.margin;
  }, 0);

  if (isLoading) {
    return (
      <Card className="h-full">
        <CardContent className="flex items-center justify-center h-full">
          <div className="text-center">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary mx-auto mb-2"></div>
            <div className="text-sm text-muted-foreground">
              Loading positions...
            </div>
          </div>
        </CardContent>
      </Card>
    );
  }

  if (error) {
    return (
      <Card className="h-full">
        <CardContent className="flex items-center justify-center h-full">
          <div className="text-center text-red-500">
            <div className="text-sm">Error loading positions</div>
            <div className="text-xs text-muted-foreground mt-1">
              {error.message}
            </div>
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="h-full">
      <CardHeader className="pb-3">
        <div className="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4">
          <div className="flex flex-col sm:flex-row sm:items-center gap-4">
            {/* Tab Navigation */}
            <div className="flex gap-1 p-1 bg-muted rounded-lg">
              {(["open", "closed"] as const).map((tab) => (
                <motion.button
                  key={tab}
                  onClick={() => setActiveTab(tab)}
                  className={cn(
                    "relative px-3 sm:px-4 py-2 text-xs font-medium rounded-md transition-colors duration-200",
                    activeTab === tab
                      ? "text-foreground"
                      : "text-muted-foreground hover:text-foreground"
                  )}
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                >
                  {activeTab === tab && (
                    <motion.div
                      layoutId="activeTab"
                      className="absolute inset-0 bg-background rounded-md shadow-sm"
                      initial={false}
                      transition={{
                        type: "spring",
                        stiffness: 500,
                        damping: 30,
                      }}
                    />
                  )}
                  <span className="relative capitalize">
                    {tab === "open" ? "Open Positions" : "Closed Positions"}
                  </span>
                </motion.button>
              ))}
            </div>

            {/* Position Count and Refresh */}
            <div className="flex items-center gap-2">
              <Badge variant="secondary" className="text-xs w-fit">
                {filteredPositions.length} positions
              </Badge>
              <Button
                variant="ghost"
                size="sm"
                onClick={async () => {
                  console.log("🔄 Manual refresh button clicked");
                  await refreshPortfolio();
                }}
                className="h-6 w-6 p-0"
                disabled={isFetching}
              >
                <svg
                  className={cn("h-3 w-3", isFetching && "animate-spin")}
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                  />
                </svg>
              </Button>
            </div>
          </div>

          {/* Summary Stats */}
          <div className="flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-4 text-xs">
            <div>
              <span className="text-muted-foreground">Total PnL: </span>
              <span
                className={cn(
                  "font-mono font-bold",
                  totalPnl >= 0 ? "text-green-500" : "text-red-500"
                )}
              >
                {totalPnl >= 0 ? "+" : ""}
                {totalPnl.toFixed(2)} USDC
              </span>
            </div>
            <div>
              <span className="text-muted-foreground">Total Margin: </span>
              <span className="font-mono">{totalMargin.toFixed(2)} USDC</span>
            </div>
            {positionsData?.accountBalance && (
              <>
                <div>
                  <span className="text-muted-foreground">Free Margin: </span>
                  <span className="font-mono text-green-500">
                    {positionsData.accountBalance.freeMargin.toFixed(2)} USDC
                  </span>
                </div>
                <div>
                  <span className="text-muted-foreground">Wallet: </span>
                  <span className="font-mono">
                    {positionsData.accountBalance.walletUSDC.toFixed(0)} USDC
                  </span>
                </div>
              </>
            )}
          </div>
        </div>

        {/* Filters */}
        <div className="flex flex-col sm:flex-row sm:items-center gap-3 pt-2">
          {/* Side Filter */}
          <div className="flex gap-1">
            {(["all", "long", "short"] as const).map((filter) => (
              <Button
                key={filter}
                variant={sideFilter === filter ? "default" : "ghost"}
                size="sm"
                onClick={() => setSideFilter(filter)}
                className={cn(
                  "text-xs h-7",
                  sideFilter === filter
                    ? "text-primary-foreground"
                    : "text-foreground hover:text-primary"
                )}
              >
                {filter === "all"
                  ? "All"
                  : filter === "long"
                  ? "Long"
                  : "Short"}
              </Button>
            ))}
          </div>

          {/* Search */}
          <div className="flex-1 sm:max-w-xs">
            <Input
              placeholder="Search markets..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="h-7 text-xs"
            />
          </div>
        </div>
      </CardHeader>

      <CardContent className="p-0">
        {/* Table Header */}
        <div className="hidden lg:grid lg:grid-cols-11 gap-2 px-4 py-2 text-xs text-muted-foreground border-b border-border bg-muted/20">
          <span>ID</span>
          <span>Market</span>
          <span>Side</span>
          <span className="text-right">Size (VETH)</span>
          <span className="text-right">Entry Price</span>
          <span className="text-right">Mark Price</span>
          <span className="text-right">Notional</span>
          <span className="text-right">PnL</span>
          <span className="text-right">Leverage</span>
          <span className="text-right">Margin</span>
          <span className="text-right">Liquidation</span>
        </div>

        {/* Position Rows */}
        <div className="max-h-64 overflow-y-auto">
          <AnimatePresence>
            {filteredPositions.length === 0 ? (
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                className="flex items-center justify-center py-8 text-muted-foreground"
              >
                <div className="text-center">
                  <div className="text-2xl mb-2">📊</div>
                  <div className="text-sm">No {activeTab} positions found</div>
                </div>
              </motion.div>
            ) : (
              filteredPositions.map((position, index) => (
                <motion.div
                  key={position.tokenId}
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  className="hover:bg-muted/30 transition-colors border-b border-border/50 cursor-pointer group"
                  onClick={() => {
                    setSelectedPosition(position);
                    setIsModalOpen(true);
                  }}
                >
                  <div className="hidden lg:grid lg:grid-cols-11 gap-2 px-4 py-3 text-xs font-mono">
                    <div className="flex items-center gap-1">
                      <span className="text-muted-foreground font-mono text-[10px]">
                        #{position.tokenId}
                      </span>
                      <svg
                        className="w-3 h-3 text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          strokeWidth={2}
                          d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
                        />
                        <path
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          strokeWidth={2}
                          d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                        />
                      </svg>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="font-medium">ETH/USDC</span>
                    </div>

                    <Badge
                      variant="outline"
                      className={cn(
                        "w-fit text-[10px] h-5 border-0",
                        position.isLong
                          ? "text-white bg-green-600"
                          : "text-white bg-red-600"
                      )}
                    >
                      {position.isLong ? "LONG" : "SHORT"}
                    </Badge>

                    <span className="text-right">
                      {position.sizeBase.toFixed(4)}
                    </span>
                    <span className="text-right">
                      {position.entryPrice.toFixed(2)}
                    </span>
                    <span className="text-right">
                      {positionsData?.currentMarkPrice?.toFixed(2) ||
                        position.currentPrice.toFixed(2)}
                    </span>
                    <span className="text-right">
                      {position.currentNotional.toFixed(2)}
                    </span>

                    <div className="text-right">
                      <div
                        className={cn(
                          "font-bold",
                          position.unrealizedPnL >= 0
                            ? "text-green-500"
                            : "text-red-500"
                        )}
                      >
                        {position.unrealizedPnL >= 0 ? "+" : ""}
                        {position.unrealizedPnL.toFixed(2)}
                      </div>
                      <div
                        className={cn(
                          "text-[10px]",
                          position.pnlPercentage >= 0
                            ? "text-green-500/70"
                            : "text-red-500/70"
                        )}
                      >
                        ({position.pnlPercentage >= 0 ? "+" : ""}
                        {position.pnlPercentage.toFixed(2)}%)
                      </div>
                    </div>

                    <span className="text-right">
                      {position.leverage.toFixed(2)}x
                    </span>
                    <span className="text-right">
                      {position.margin.toFixed(2)}
                    </span>
                    <span className="text-right text-muted-foreground">
                      {position.liquidationPrice.toFixed(2)}
                    </span>
                  </div>

                  <div className="lg:hidden p-4 space-y-3">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <div className="flex flex-col">
                          <span className="font-medium text-sm">ETH/USDC</span>
                          <span className="text-xs text-muted-foreground font-mono">
                            ID: #{position.tokenId}
                          </span>
                        </div>
                      </div>
                      <Badge
                        variant="outline"
                        className={cn(
                          "text-xs border-0",
                          position.isLong
                            ? "text-white bg-green-600"
                            : "text-white bg-red-600"
                        )}
                      >
                        {position.isLong ? "Long" : "Short"}
                      </Badge>
                    </div>

                    <div className="grid grid-cols-2 gap-3 text-xs">
                      <div>
                        <span className="text-muted-foreground">Size:</span>
                        <div className="font-mono">
                          {position.sizeBase.toFixed(4)} VETH
                        </div>
                      </div>
                      <div>
                        <span className="text-muted-foreground">Leverage:</span>
                        <div className="font-mono">
                          {position.leverage.toFixed(2)}x
                        </div>
                      </div>
                      <div>
                        <span className="text-muted-foreground">Entry:</span>
                        <div className="font-mono">
                          {position.entryPrice.toFixed(2)} USDC
                        </div>
                      </div>
                      <div>
                        <span className="text-muted-foreground">Mark:</span>
                        <div className="font-mono">
                          {positionsData?.currentMarkPrice?.toFixed(2) ||
                            position.currentPrice.toFixed(2)}{" "}
                          USDC
                        </div>
                      </div>
                      <div>
                        <span className="text-muted-foreground">Notional:</span>
                        <div className="font-mono">
                          {position.currentNotional.toFixed(2)} USDC
                        </div>
                      </div>
                      <div>
                        <span className="text-muted-foreground">
                          Liquidation:
                        </span>
                        <div className="font-mono">
                          {position.liquidationPrice.toFixed(2)} USDC
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center justify-between pt-2 border-t border-border/50">
                      <div>
                        <span className="text-muted-foreground text-xs">
                          PnL:
                        </span>
                        <div
                          className={cn(
                            "font-mono font-bold",
                            position.unrealizedPnL >= 0
                              ? "text-green-500"
                              : "text-red-500"
                          )}
                        >
                          {position.unrealizedPnL >= 0 ? "+" : ""}
                          {position.unrealizedPnL.toFixed(2)} USDC
                          <span className="ml-1 text-xs opacity-70">
                            ({position.pnlPercentage >= 0 ? "+" : ""}
                            {position.pnlPercentage.toFixed(2)}%)
                          </span>
                        </div>
                      </div>
                      <div className="text-right">
                        <span className="text-muted-foreground text-xs">
                          Margin:
                        </span>
                        <div className="font-mono text-sm">
                          {position.margin.toFixed(0)} USDC
                        </div>
                      </div>
                    </div>
                  </div>
                </motion.div>
              ))
            )}
          </AnimatePresence>
        </div>
      </CardContent>

      {/* Position Management Modal */}
      <PositionManagementModal
        position={selectedPosition}
        isOpen={isModalOpen}
        onClose={() => {
          setIsModalOpen(false);
          setSelectedPosition(null);
        }}
      />
    </Card>
  );
}
