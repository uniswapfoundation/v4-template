"use client";

import { useState } from "react";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/core";
import { useAccount, useBalance } from "wagmi";
import { encodeAbiParameters, keccak256 } from "viem";
import { WalletConnectButton } from "./wallet-connect-button";
import { motion } from "framer-motion";
import { useMarket } from "@/context/market-context";
import {
  usePositionManagement,
  calculatePoolId,
  calculatePositionSize,
} from "@/hooks/api/use-positions";
import { useMarketData } from "@/hooks/api/use-market-data";
import { getContracts } from "@/lib/core";
import { toast } from "sonner";
import { calculateRequiredMargin, validatePositionParams } from "@/lib/core";
import { usePortfolioRefresh } from "@/hooks/use-portfolio-refresh";
import { portfolioEvents } from "@/lib/core";
import { Loader2, TrendingUp, TrendingDown, Receipt } from "lucide-react";

export default function TradingPanel() {
  const [orderType, setOrderType] = useState<"Market" | "Limit">("Market");
  const [side, setSide] = useState<"Buy" | "Sell">("Buy");
  const [leverage, setLeverage] = useState(1);
  const [margin, setMargin] = useState("");
  const [isTransactionPending, setIsTransactionPending] = useState(false);

  const { address, isConnected } = useAccount();
  const { data: balance } = useBalance({
    address,
    query: {
      enabled: !!address,
    },
  });

  // Get current market from context
  const { selectedMarket } = useMarket();

  // Get market details for current market - use ETH for the API
  const { marketDetails, marketDetailsLoading: marketLoading } =
    useMarketData();

  console.log("🔍 Market details loading:", marketLoading);
  console.log("🔍 Market details data:", marketDetails);

  // Position management hooks
  const {
    openPosition,
    closePosition,
    isLoading: positionLoading,
  } = usePositionManagement();
  const { refreshPortfolio } = usePortfolioRefresh();

  // Debug loading states
  console.log("🔍 Loading states:", {
    marketLoading,
    positionLoading,
    openPositionPending: openPosition.isPending,
    margin: margin,
    isConnected,
  });

  const leverageOptions = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

  const handleLeverageChange = (value: number) => {
    setLeverage(value);
  };

  // Calculate position size based on margin and leverage
  const calculatePositionSize = () => {
    if (!margin) return 0;
    const marginValue = parseFloat(margin);
    const price = marketDetails?.currentPrice || 2000; // Fallback to $2000
    return (marginValue * leverage) / price;
  };

  // Update size when margin or leverage changes
  const handleMarginChange = (value: string) => {
    setMargin(value);
  };

  const handleTrade = async () => {
    console.log("🚀 Buy button clicked!");
    console.log("Wallet connected:", isConnected);
    console.log("Address:", address);
    console.log("Margin:", margin);
    console.log("Selected market:", selectedMarket);
    console.log("Market details:", marketDetails);

    if (!isConnected) {
      toast.error("Please connect your wallet first.");
      return;
    }

    if (!margin || !selectedMarket) {
      toast.error("Please enter margin amount.");
      return;
    }

    // Use fallback price if market details not available
    const currentPrice = marketDetails?.currentPrice || 2000; // Fallback to $2000
    console.log("💰 Using price:", currentPrice);

    // Calculate position size
    const size = calculatePositionSize();
    console.log("📊 Calculated position size:", size);
    console.log(
      "📊 Input values - Margin:",
      margin,
      "Leverage:",
      leverage,
      "Price:",
      currentPrice
    );
    console.log(
      "📊 Calculation: (",
      margin,
      "*",
      leverage,
      ") /",
      currentPrice,
      "=",
      size
    );

    // Validate position parameters
    const validation = validatePositionParams(
      size,
      parseFloat(margin),
      leverage,
      currentPrice
    );
    console.log("✅ Validation result:", validation);

    if (!validation.valid) {
      console.log("❌ Validation failed:", validation.error);
      toast.error(validation.error);
      return;
    }

    console.log("✅ Validation passed, proceeding to contract call...");
    setIsTransactionPending(true);

    try {
      // Calculate pool ID using the exact same method as the working script
      const contracts = getContracts();
      const fee = 3000; // 0.3%
      const tickSpacing = 60;
      const hooks = contracts.perpsHook.address;

      // Order currencies by address (lower address = currency0) - same as script
      const [currency0, currency1] =
        contracts.mockUSDC.address.toLowerCase() <
        contracts.mockVETH.address.toLowerCase()
          ? [contracts.mockUSDC.address, contracts.mockVETH.address]
          : [contracts.mockVETH.address, contracts.mockUSDC.address];

      console.log("💱 Pool Configuration:");
      console.log("  Currency0:", currency0);
      console.log("  Currency1:", currency1);
      console.log("  Fee:", fee, "bps");
      console.log("  Hook:", hooks);

      // Calculate poolId using the same method as Uniswap V4
      const poolKeyEncoded = encodeAbiParameters(
        [
          { type: "address", name: "currency0" },
          { type: "address", name: "currency1" },
          { type: "uint24", name: "fee" },
          { type: "int24", name: "tickSpacing" },
          { type: "address", name: "hooks" },
        ],
        [currency0, currency1, fee, tickSpacing, hooks]
      );
      const poolId = keccak256(poolKeyEncoded);
      console.log("🆔 Calculated pool ID:", poolId);

      const result = await openPosition.mutateAsync({
        marketId: poolId,
        size: size,
        leverage,
        margin: parseFloat(margin),
        isLong: side === "Buy",
      });

      console.log("🎉 Position opened successfully, refreshing portfolio...");

      // Emit portfolio update event
      portfolioEvents.notify();

      // Refresh portfolio data after successful position opening
      await refreshPortfolio();

      // Also manually refetch with a small delay to ensure the transaction is processed
      setTimeout(async () => {
        console.log("🔄 Delayed portfolio refresh...");
        portfolioEvents.notify();
        await refreshPortfolio();
      }, 3000);

      toast.success(
        `Successfully opened ${side} position. Transaction: ${result.txHash.slice(
          0,
          10
        )}...`
      );

      // Reset form
      setMargin("");

      // Stop loading after transaction is confirmed
      setIsTransactionPending(false);
    } catch (error) {
      console.error("Error opening position:", error);
      toast.error(
        error instanceof Error ? error.message : "Failed to open position"
      );

      // Stop loading on error
      setIsTransactionPending(false);
    }
  };

  // Reset form when switching between Buy/Sell
  const handleSideChange = (newSide: "Buy" | "Sell") => {
    setSide(newSide);
    // Clear form when switching sides
    setMargin("");
  };

  return (
    <Card className="h-full">
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <div className="flex gap-1">
            {(["Market"] as const).map((type) => (
              <Button
                key={type}
                variant={orderType === type ? "default" : "ghost"}
                size="sm"
                onClick={() => setOrderType(type)}
                className="text-xs"
              >
                {type}
              </Button>
            ))}
          </div>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Buy/Sell Toggle */}
        <div className="relative p-1 bg-muted rounded-lg">
          {/* Animated slider background */}
          <motion.div
            className={cn(
              "absolute top-1 bottom-1 w-[calc(50%-2px)] rounded-md",
              side === "Buy" ? "bg-success" : "bg-destructive"
            )}
            initial={false}
            animate={{
              x: side === "Buy" ? 0 : "calc(100% + 4px)",
            }}
            transition={{
              type: "spring",
              stiffness: 300,
              damping: 30,
            }}
          />

          {/* Toggle buttons */}
          <div className="relative grid grid-cols-2 gap-1">
            {(["Buy", "Sell"] as const).map((option) => (
              <button
                key={option}
                onClick={() => handleSideChange(option)}
                className={cn(
                  "relative z-10 py-2 px-4 text-xs font-medium rounded-md transition-colors duration-200",
                  side === option
                    ? "text-white"
                    : "text-muted-foreground hover:text-foreground"
                )}
              >
                {option}
              </button>
            ))}
          </div>
        </div>

        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <Label className="text-xs">Leverage</Label>
            <div className="flex items-center gap-2">
              {marketLoading ? (
                <div className="flex items-center gap-1">
                  <div className="h-4 w-8 bg-muted animate-pulse rounded"></div>
                  <Loader2 className="w-3 h-3 animate-spin text-muted-foreground" />
                </div>
              ) : (
                <motion.div
                  key={leverage}
                  initial={{ scale: 1.2, opacity: 0.8 }}
                  animate={{ scale: 1, opacity: 1 }}
                  transition={{ duration: 0.2 }}
                  className="text-xs font-mono font-bold text-primary"
                >
                  {leverage}x
                </motion.div>
              )}
            </div>
          </div>

          <div className="relative">
            {/* Slider track */}
            <div className="h-2 bg-muted rounded-full relative overflow-hidden">
              {/* Animated progress fill */}
              <motion.div
                className="absolute top-0 left-0 h-full bg-gradient-to-r from-success via-warning to-destructive rounded-full"
                initial={{ width: "10%" }}
                animate={{
                  width: `${
                    ((leverageOptions.indexOf(leverage) + 1) /
                      leverageOptions.length) *
                    100
                  }%`,
                }}
                transition={{
                  type: "spring",
                  stiffness: 400,
                  damping: 30,
                }}
              />

              {/* Animated thumb */}
              <motion.div
                className="absolute top-1/2 -translate-y-1/2 w-4 h-4 bg-white border-2 border-primary rounded-full shadow-lg cursor-pointer"
                initial={{ left: "10%" }}
                animate={{
                  left: `${
                    (leverageOptions.indexOf(leverage) /
                      (leverageOptions.length - 1)) *
                    100
                  }%`,
                  x: "-50%",
                }}
                transition={{
                  type: "spring",
                  stiffness: 400,
                  damping: 30,
                }}
                whileHover={{ scale: 1.1 }}
                whileTap={{ scale: 0.95 }}
              />
            </div>

            {/* Leverage options */}
            <div className="flex justify-between mt-2">
              {leverageOptions.map((option, index) => (
                <motion.button
                  key={option}
                  onClick={() => handleLeverageChange(option)}
                  disabled={marketLoading}
                  className={cn(
                    "text-xs px-2 py-1 rounded transition-all duration-200",
                    marketLoading
                      ? "opacity-50 cursor-not-allowed"
                      : leverage === option
                      ? "text-white font-bold bg-primary"
                      : "text-foreground hover:text-primary hover:bg-muted/50"
                  )}
                  whileHover={marketLoading ? {} : { scale: 1.05 }}
                  whileTap={marketLoading ? {} : { scale: 0.95 }}
                >
                  {option}
                </motion.button>
              ))}
            </div>
          </div>
        </div>

        {/* Available to Trade */}
        <div className="text-xs text-muted-foreground">
          <div className="flex justify-between">
            <span>Available to Trade</span>
            {marketLoading ? (
              <div className="flex items-center gap-1">
                <div className="h-4 w-20 bg-muted animate-pulse rounded"></div>
                <Loader2 className="w-3 h-3 animate-spin text-muted-foreground" />
              </div>
            ) : (
              <span className="font-mono">
                {isConnected && balance
                  ? `${Number.parseFloat(balance.formatted).toFixed(4)} ${
                      balance.symbol
                    }`
                  : "0.00 USDC"}
              </span>
            )}
          </div>
        </div>

        {/* Margin Input */}
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <Label htmlFor="margin" className="text-xs">
              Margin (USDC)
            </Label>
            <div className="flex gap-1">
              {[50, 100, 200, 500].map((amount) => (
                <Button
                  key={amount}
                  variant="ghost"
                  size="sm"
                  className="h-6 px-2 text-xs"
                  disabled={marketLoading}
                  onClick={() => handleMarginChange(amount.toString())}
                >
                  ${amount}
                </Button>
              ))}
            </div>
          </div>
          <div className="relative">
            <Input
              id="margin"
              placeholder={marketLoading ? "Loading market data..." : "0"}
              className="pr-12 font-mono"
              disabled={!isConnected || marketLoading}
              value={margin}
              onChange={(e) => handleMarginChange(e.target.value)}
            />
            <div className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-muted-foreground flex items-center gap-1">
              {marketLoading && <Loader2 className="w-3 h-3 animate-spin" />}
              USDC
            </div>
          </div>
        </div>

        {/* Position Value Display */}
        {margin && (
          <div className="space-y-1 text-xs p-3 bg-muted/30 rounded-lg">
            <div className="flex justify-between">
              <span className="text-muted-foreground">Position Value:</span>
              {marketLoading ? (
                <div className="flex items-center gap-1">
                  <div className="h-4 w-16 bg-muted animate-pulse rounded"></div>
                  <Loader2 className="w-3 h-3 animate-spin text-muted-foreground" />
                </div>
              ) : (
                <span className="font-mono font-semibold">
                  $
                  {(
                    calculatePositionSize() *
                    (marketDetails?.currentPrice || 2000)
                  ).toFixed(2)}
                </span>
              )}
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Leverage:</span>
              <span className="font-mono">{leverage}x</span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Margin Required:</span>
              <span className="font-mono">{margin} USDC</span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Position Type:</span>
              <span
                className={cn(
                  "font-mono font-semibold",
                  side === "Buy" ? "text-green-500" : "text-red-500"
                )}
              >
                {side === "Buy" ? "LONG" : "SHORT"}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">
                Size ({selectedMarket?.symbol?.split("/")[0] || "ETH"}):
              </span>
              {marketLoading ? (
                <div className="flex items-center gap-1">
                  <div className="h-4 w-20 bg-muted animate-pulse rounded"></div>
                  <Loader2 className="w-3 h-3 animate-spin text-muted-foreground" />
                </div>
              ) : (
                <span className="font-mono">
                  {calculatePositionSize().toFixed(6)}
                </span>
              )}
            </div>
          </div>
        )}

        {!isConnected ? (
          <WalletConnectButton />
        ) : (
          <Button
            onClick={handleTrade}
            disabled={
              !margin ||
              marketLoading ||
              positionLoading ||
              openPosition.isPending ||
              isTransactionPending
            }
            className={cn(
              "w-full transition-all duration-300",
              side === "Buy"
                ? "bg-success hover:bg-success/90 disabled:opacity-50 disabled:cursor-not-allowed"
                : "bg-destructive hover:bg-destructive/90 disabled:opacity-50 disabled:cursor-not-allowed"
            )}
          >
            <div className="flex items-center justify-center gap-2">
              {marketLoading ||
              positionLoading ||
              openPosition.isPending ||
              isTransactionPending ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : side === "Buy" ? (
                <TrendingUp className="w-4 h-4" />
              ) : (
                <TrendingDown className="w-4 h-4" />
              )}
              {marketLoading || positionLoading
                ? "Loading Market Data..."
                : openPosition.isPending || isTransactionPending
                ? "Opening Position..."
                : `${side} ${selectedMarket?.symbol || "ETH"}`}
            </div>
          </Button>
        )}

        {/* Risk Warning */}
        {leverage > 3 && (
          <div className="p-3 bg-orange-500/10 border border-orange-500/20 rounded-lg">
            <div className="flex items-center gap-2 text-xs text-orange-600">
              <div className="w-4 h-4 rounded-full bg-orange-500 flex items-center justify-center">
                <span className="text-white text-[10px] font-bold">!</span>
              </div>
              <span className="font-semibold">High Leverage Warning</span>
            </div>
            <div className="text-xs text-orange-600/80 mt-1">
              {leverage}x leverage amplifies both gains and losses. You could
              lose more than your margin.
            </div>
          </div>
        )}

        {/* Order Details */}
        <div className="space-y-2 text-xs">
          <div className="flex justify-between">
            <span className="text-muted-foreground">Order Value</span>
            {marketLoading ? (
              <div className="flex items-center gap-1">
                <div className="h-4 w-16 bg-muted animate-pulse rounded"></div>
                <Loader2 className="w-3 h-3 animate-spin text-muted-foreground" />
              </div>
            ) : (
              <span className="font-mono">
                {margin
                  ? `$${(
                      calculatePositionSize() *
                      (marketDetails?.currentPrice || 2000)
                    ).toFixed(2)}`
                  : "N/A"}
              </span>
            )}
          </div>
          <div className="flex justify-between">
            <span className="text-muted-foreground">Liquidation Price</span>
            {marketLoading ? (
              <div className="flex items-center gap-1">
                <div className="h-4 w-20 bg-muted animate-pulse rounded"></div>
                <Loader2 className="w-3 h-3 animate-spin text-muted-foreground" />
              </div>
            ) : (
              <span className="font-mono text-orange-500">
                {margin
                  ? `$${(
                      (marketDetails?.currentPrice || 2000) *
                      (1 -
                        (parseFloat(margin) /
                          (calculatePositionSize() *
                            (marketDetails?.currentPrice || 2000))) *
                          0.9)
                    ).toFixed(2)}`
                  : "N/A"}
              </span>
            )}
          </div>
          <div className="flex justify-between">
            <span className="text-muted-foreground">Fees</span>
            {marketLoading ? (
              <div className="flex items-center gap-1">
                <div className="h-4 w-24 bg-muted animate-pulse rounded"></div>
                <Loader2 className="w-3 h-3 animate-spin text-muted-foreground" />
              </div>
            ) : (
              <span className="font-mono flex items-center gap-1">
                <Receipt className="w-3 h-3 text-muted-foreground" />
                {marketDetails?.fees
                  ? `${(marketDetails.fees.taker * 100).toFixed(4)}% / ${(
                      marketDetails.fees.maker * 100
                    ).toFixed(4)}%`
                  : "0.0600% / 0.0300%"}
              </span>
            )}
          </div>
        </div>

        {isConnected && address && (
          <div className="pt-2 border-t border-border">
            <div className="text-xs text-muted-foreground">
              <div className="flex justify-between">
                <span>Wallet</span>
                <span className="font-mono">
                  {address.slice(0, 6)}...{address.slice(-4)}
                </span>
              </div>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
