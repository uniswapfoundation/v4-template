"use client";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
// import { useTradesStream } from "@/hooks/api/use-trades-stream";
import { useMarket } from "@/context/market-context";

export default function OrderBook() {
  const { selectedMarket } = useMarket();

  // TODO: Re-enable trades stream when ready
  // const { trades, currentPrice, isConnected, error, isLoading } =
  //   useTradesStream({
  //     marketId: selectedMarket?.symbol || "ETH",
  //     enabled: true,
  //   });

  // Placeholder data for now
  const trades = {
    long: [] as Array<{
      id: string;
      price: number;
      size: number;
      timestamp: string;
    }>,
    short: [] as Array<{
      id: string;
      price: number;
      size: number;
      timestamp: string;
    }>,
  };
  const currentPrice = 0;
  const isConnected = false;
  const error = null;
  const isLoading = false;

  // Get latest 10 trades for each side
  const latestLongTrades = trades.long.slice(0, 10);
  const latestShortTrades = trades.short.slice(0, 10);

  if (isLoading) {
    return (
      <Card className="h-full">
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <div className="w-2 h-2 rounded-full bg-primary"></div>
              <h3 className="text-sm font-semibold">Trades</h3>
            </div>
            <div className="text-xs text-muted-foreground">Live</div>
          </div>
        </CardHeader>
        <CardContent className="flex items-center justify-center h-32">
          <div className="text-center">
            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-primary mx-auto mb-2"></div>
            <div className="text-xs text-muted-foreground">
              Loading trades...
            </div>
          </div>
        </CardContent>
      </Card>
    );
  }

  if (error) {
    return (
      <Card className="h-full">
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <div className="w-2 h-2 rounded-full bg-primary"></div>
              <h3 className="text-sm font-semibold">Trades</h3>
            </div>
            <div className="text-xs text-muted-foreground">Live</div>
          </div>
        </CardHeader>
        <CardContent className="flex items-center justify-center h-32">
          <div className="text-center text-red-500">
            <div className="text-xs">Connection Error</div>
            <div className="text-xs text-muted-foreground mt-1">{error}</div>
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="h-full">
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 rounded-full bg-primary"></div>
            <h3 className="text-sm font-semibold">Trades</h3>
          </div>
          <div className="text-xs text-muted-foreground">Live</div>
        </div>

        <div className="grid grid-cols-3 gap-4 text-xs text-muted-foreground pt-4 pb-2 px-1 border-t border-border/50">
          <span className="font-medium">Price</span>
          <span className="text-right font-medium">Size</span>
          <span className="text-right font-medium">Time</span>
        </div>
      </CardHeader>

      <CardContent className="p-0 space-y-0">
        {/* Short Trades (Red) - Top */}
        <div className="space-y-0">
          {latestShortTrades.map((trade, index) => (
            <div
              key={trade.id}
              className="grid grid-cols-3 gap-4 px-4 py-1 text-xs font-mono hover:bg-red-500/5"
            >
              <span className="text-red-400">${trade.price.toFixed(2)}</span>
              <span className="text-right">{trade.size.toFixed(2)}</span>
              <span className="text-right text-muted-foreground">
                {new Date(trade.timestamp).toLocaleTimeString()}
              </span>
            </div>
          ))}
        </div>

        {/* Spread/Divider */}
        <div className="px-4 py-2 bg-muted/10 border-y border-border/50">
          <div className="grid grid-cols-3 gap-4 text-xs">
            <span className="text-muted-foreground">Spread</span>
            <span className="font-mono text-right">
              {currentPrice ? (currentPrice * 0.001).toFixed(3) : "0.000"}
            </span>
            <span className="font-mono text-right">
              {currentPrice ? "0.1%" : "0%"}
            </span>
          </div>
        </div>

        {/* Long Trades (Green) - Bottom */}
        <div className="space-y-0">
          {latestLongTrades.map((trade, index) => (
            <div
              key={trade.id}
              className="grid grid-cols-3 gap-4 px-4 py-1 text-xs font-mono hover:bg-green-500/5"
            >
              <span className="text-green-400">${trade.price.toFixed(2)}</span>
              <span className="text-right">{trade.size.toFixed(2)}</span>
              <span className="text-right text-muted-foreground">
                {new Date(trade.timestamp).toLocaleTimeString()}
              </span>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
