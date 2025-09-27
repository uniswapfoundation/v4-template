import { NextRequest } from "next/server";
import fs from "fs";
import path from "path";
import { eventListener } from "@/lib/events";

interface PositionEvent {
  type: "position_opened" | "position_closed";
  tokenId: string;
  owner: string;
  marketId: string;
  sizeBase: string;
  entryPrice: string;
  margin: string;
  pnl?: string;
  side: "long" | "short" | "closed";
  timestamp: string;
  blockNumber: bigint;
  transactionHash: string;
}

// GET /api/trades-stream - Stream trades with random price updates
export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const marketId = searchParams.get("marketId") || "ETH";

  // Set up SSE headers
  const headers = new Headers({
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Cache-Control",
  });

  // Create a readable stream
  const stream = new ReadableStream({
    start(controller) {
      // Send initial data
      const sendData = (data: any) => {
        const message = `data: ${JSON.stringify(data)}\n\n`;
        controller.enqueue(new TextEncoder().encode(message));
      };

      // Send initial connection message
      sendData({
        type: "connection",
        message: "Connected to trades stream",
        marketId,
        timestamp: new Date().toISOString(),
      });

      // Load initial trades data
      let tradesData: any = {};
      try {
        const dataPath = path.join(
          process.cwd(),
          "backend",
          "data",
          "trades.json"
        );
        const fileContents = fs.readFileSync(dataPath, "utf8");
        tradesData = JSON.parse(fileContents);
      } catch (error) {
        console.error("Error loading trades data:", error);
      }

      // Base prices for random generation
      const basePrices: { [key: string]: number } = {
        ETH: 2500,
        BTC: 41500,
        SOL: 98,
      };

      let currentPrices = { ...basePrices };

      // Convert position event to trade format
      const convertPositionToTrade = (event: PositionEvent) => {
        const sizeBase = BigInt(event.sizeBase);
        const entryPrice = BigInt(event.entryPrice);
        const margin = BigInt(event.margin);

        // Convert from wei to readable units
        const size = Number(sizeBase) / 1e18; // VETH has 18 decimals
        const price = Number(entryPrice) / 1e18; // Price in 1e18 precision
        const marginAmount = Number(margin) / 1e6; // USDC has 6 decimals

        return {
          id: `position_${event.tokenId}`,
          market: event.marketId || "ETH", // Use marketId or default to ETH
          side: event.side,
          size: Math.abs(size), // Always positive size
          price: Math.round(price * 100) / 100,
          margin: marginAmount,
          owner: event.owner,
          tokenId: event.tokenId,
          timestamp: event.timestamp,
          blockNumber: event.blockNumber.toString(),
          transactionHash: event.transactionHash,
        };
      };

      // Send initial trades data
      if (tradesData[marketId]) {
        sendData({
          type: "initial_trades",
          data: tradesData[marketId],
          marketId,
          timestamp: new Date().toISOString(),
        });
      }

      // Subscribe to real position events
      const handlePositionEvent = (event: PositionEvent) => {
        try {
          // Only process position opened events for now
          if (event.type === "position_opened") {
            const trade = convertPositionToTrade(event);

            // Send new position as trade
            sendData({
              type: "new_trade",
              data: trade,
              marketId: trade.market,
              timestamp: new Date().toISOString(),
            });

            // Update current price
            currentPrices[trade.market] = trade.price;

            // Send price update
            sendData({
              type: "price_update",
              data: {
                market: trade.market,
                price: trade.price,
                timestamp: new Date().toISOString(),
              },
              marketId: trade.market,
              timestamp: new Date().toISOString(),
            });
          }
        } catch (error) {
          console.error("Error processing position event:", error);
        }
      };

      // Subscribe to blockchain events
      eventListener.subscribe(handlePositionEvent);

      // Cleanup function
      const cleanup = () => {
        // Unsubscribe from events
        eventListener.unsubscribe(handlePositionEvent);
        try {
          controller.close();
        } catch (error) {
          console.error("Error closing stream:", error);
        }
      };

      // Handle client disconnect
      request.signal.addEventListener("abort", cleanup);

      // Send keepalive every 30 seconds
      const keepAliveInterval = setInterval(() => {
        try {
          sendData({
            type: "keepalive",
            message: "Connection alive",
            timestamp: new Date().toISOString(),
          });
        } catch (error) {
          clearInterval(keepAliveInterval);
          cleanup();
        }
      }, 30000);

      // Cleanup keepalive on abort
      request.signal.addEventListener("abort", () => {
        clearInterval(keepAliveInterval);
        cleanup();
      });
    },
  });

  return new Response(stream, { headers });
}
