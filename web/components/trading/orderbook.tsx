"use client";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { useEffect, useState } from "react";

// Simple interface for positions from backend
interface BackendPosition {
  tokenId: string;
  trader: string;
  market: string;
  side: 'Long' | 'Short';
  size: string;
  entryPrice: string;
  margin: string;
  leverage: string;
  timestamp: Date;
  transactionHash: string;
  status: 'Open' | 'Closed';
}

// Trade interface for UI display
interface Trade {
  id: string;
  price: number;
  size: number;
  timestamp: string;
  type: 'long' | 'short';
}

export default function OrderBook() {
  const [positions, setPositions] = useState<BackendPosition[]>([]);
  const [isConnected, setIsConnected] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    console.log('🚀 Starting WebSocket connection');
    
    const ws = new WebSocket('ws://localhost:8080');
    
    ws.onopen = () => {
      console.log('✅ WebSocket connected!');
      setIsConnected(true);
      setError(null);
      setIsLoading(false);
    };
    
    ws.onmessage = (event) => {
      try {
        const message = JSON.parse(event.data);
        console.log('📊 Received message:', message);
        
        if (message.type === 'INITIAL_POSITIONS' && message.data) {
          console.log('� Setting initial positions:', message.data);
          setPositions(message.data);
        } else if (message.type === 'POSITION_OPENED' && message.data) {
          console.log('🆕 Adding new position:', message.data);
          setPositions(prev => [message.data, ...prev]);
        } else if (message.type === 'POSITION_CLOSED' && message.data) {
          console.log('🔒 Position closed:', message.data);
          setPositions(prev => prev.filter(pos => pos.tokenId !== message.data.tokenId));
        }
      } catch (e) {
        console.error('❌ Parse error:', e);
      }
    };
    
    ws.onerror = (error) => {
      console.error('❌ WebSocket error:', error);
      setError('WebSocket connection failed');
      setIsConnected(false);
      setIsLoading(false);
    };
    
    ws.onclose = () => {
      console.log('🔌 WebSocket closed');
      setIsConnected(false);
    };
    
    return () => {
      console.log('🧹 Cleaning up WebSocket');
      ws.close();
    };
  }, []);

  // Convert positions to trades format for UI
  const trades = {
    long: positions
      .filter((pos: BackendPosition) => pos.side === 'Long' && pos.status === 'Open')
      .slice(0, 10)
      .map((pos: BackendPosition) => ({
        id: pos.tokenId,
        price: parseFloat(pos.entryPrice),
        size: parseFloat(pos.size),
        timestamp: new Date(pos.timestamp).toISOString(),
        type: 'long' as const
      })),
    short: positions
      .filter((pos: BackendPosition) => pos.side === 'Short' && pos.status === 'Open')
      .slice(0, 10)
      .map((pos: BackendPosition) => ({
        id: pos.tokenId,
        price: parseFloat(pos.entryPrice),
        size: parseFloat(pos.size),
        timestamp: new Date(pos.timestamp).toISOString(),
        type: 'short' as const
      }))
  };

  // Helper function to format large numbers
  const formatSize = (size: number): string => {
    if (size >= 1e9) return (size / 1e9).toFixed(2) + 'B';
    if (size >= 1e6) return (size / 1e6).toFixed(2) + 'M';
    if (size >= 1e3) return (size / 1e3).toFixed(2) + 'K';
    return size.toFixed(2);
  };

  // Helper function to format time
  const formatTime = (timestamp: string): string => {
    return new Date(timestamp).toLocaleTimeString([], { 
      hour: '2-digit', 
      minute: '2-digit'
    });
  };

  // Calculate current price from latest position
  const currentPrice = positions.length > 0 ? parseFloat(positions[0].entryPrice) : 0;

  // Get latest 10 trades for each side
  const latestLongTrades = trades.long.slice(0, 10);
  const latestShortTrades = trades.short.slice(0, 10);

  if (isLoading) {
    return (
      <Card className="h-full">
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <div className="w-2 h-2 rounded-full bg-yellow-500"></div>
              <h3 className="text-sm font-semibold">Trades</h3>
            </div>
            <div className="text-xs text-muted-foreground">Connecting...</div>
          </div>
        </CardHeader>
        <CardContent className="flex items-center justify-center h-32">
          <div className="text-center">
            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-primary mx-auto mb-2"></div>
            <div className="text-xs text-muted-foreground">
              Connecting to position stream...
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
              <div className="w-2 h-2 rounded-full bg-red-500"></div>
              <h3 className="text-sm font-semibold">Trades</h3>
            </div>
            <div className="text-xs text-muted-foreground">Error</div>
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
      <CardHeader className="pb-1">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className={`w-2 h-2 rounded-full ${isConnected ? 'bg-green-500' : 'bg-red-500'}`}></div>
            <h3 className="text-sm font-semibold">Trades</h3>
          </div>
          <div className="text-xs text-muted-foreground">
            {isConnected ? 'Live' : 'Disconnected'}
          </div>
        </div>

        {/* Spread section at top */}
        <div className="grid grid-cols-3 gap-4 py-2 px-1 mt-3 border-b border-border/30">
          <span className="text-xs text-muted-foreground">Spread</span>
          <span className="text-xs font-mono text-right">
            {currentPrice ? (currentPrice * 0.001).toFixed(3) : "0.000"}
          </span>
          <span className="text-xs font-mono text-right">0%</span>
        </div>

        <div className="grid grid-cols-3 gap-4 text-xs text-muted-foreground pt-2 pb-2 px-1 border-t border-border/50">
          <span className="font-medium">Price</span>
          <span className="text-right font-medium">Size</span>
          <span className="text-right font-medium">Time</span>
        </div>
      </CardHeader>

     <CardContent className="p-0">
        {/* Price Size Time headers */}
        <div className="grid grid-cols-3 gap-4 text-xs text-muted-foreground py-2 px-4 border-t border-b border-border/50">
          <span className="font-medium">Price</span>
          <span className="text-right font-medium">Size</span>
          <span className="text-right font-medium">Time</span>
        </div>

        {/* Spread info
        <div className="grid grid-cols-3 gap-4 py-2 px-4 border-b border-border/30">
          <span className="text-xs text-muted-foreground">Spread</span>
          <span className="text-xs font-mono text-right">
            {currentPrice ? (currentPrice * 0.001).toFixed(3) : "0.000"}
          </span>
          <span className="text-xs font-mono text-right">0%</span>
        </div> */}

        {/* Show message if no trades */}
        {latestLongTrades.length === 0 && latestShortTrades.length === 0 && isConnected && (
          <div className="flex items-center justify-center h-32">
            <div className="text-center text-muted-foreground">
              <div className="text-xs">No trades yet</div>
              <div className="text-xs mt-1">Waiting for position events...</div>
            </div>
          </div>
        )}

        {/* Short Trades (Red) - Top */}
        <div className="space-y-0">
          {latestShortTrades.map((trade, index) => (
            <div
              key={trade.id}
              className="grid grid-cols-3 gap-4 px-4 py-1 text-xs font-mono hover:bg-red-500/5"
            >
              <span className="text-red-400">${trade.price.toFixed(2)}</span>
              <span className="text-right">{formatSize(trade.size)}</span>
              <span className="text-right text-muted-foreground">
                {formatTime(trade.timestamp)}
              </span>
            </div>
          ))}
        </div>

        {/* Long Trades (Green) - Bottom */}
        <div className="space-y-0">
          {latestLongTrades.map((trade, index) => (
            <div
              key={trade.id}
              className="grid grid-cols-3 gap-4 px-4 py-1 text-xs font-mono hover:bg-green-500/5"
            >
              <span className="text-green-400">${trade.price.toFixed(2)}</span>
              <span className="text-right">{formatSize(trade.size)}</span>
              <span className="text-right text-muted-foreground">
                {formatTime(trade.timestamp)}
              </span>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}