import { NextRequest, NextResponse } from "next/server";
import { HermesClient } from "@pythnetwork/hermes-client";
import { MarketList } from "@/data/market-list";

const hermesConnection = new HermesClient("https://hermes.pyth.network");

const connections = new Map<string, ReadableStreamDefaultController>();
const priceData = new Map<string, any>();
const historicalData = new Map<string, Map<string, any[]>>();

const TIMEFRAME_INTERVALS = {
  "5m": 5 * 60 * 1000,
  "30m": 30 * 60 * 1000,
  "1h": 60 * 60 * 1000,
  "5h": 5 * 60 * 60 * 1000,
  "24h": 24 * 60 * 60 * 1000,
};

function parsePriceData(rawData: any) {
  if (!rawData.parsed || !Array.isArray(rawData.parsed)) {
    return [];
  }

  return rawData.parsed.map((item: any) => {
    const priceInfo = item.price;
    return {
      id: item.id,
      price: parseFloat(priceInfo.price) / Math.pow(10, -priceInfo.expo),
      confidence: parseFloat(priceInfo.conf) / Math.pow(10, -priceInfo.expo),
      exponent: priceInfo.expo,
      publishTime: priceInfo.publish_time,
      timestamp: Date.now(),
    };
  });
}

// Aggregate data for different timeframes
function aggregateDataForTimeframe(
  data: any[],
  timeframe: string,
  limit: number = 100
) {
  if (!data.length) return [];

  const interval =
    TIMEFRAME_INTERVALS[timeframe as keyof typeof TIMEFRAME_INTERVALS];
  const now = Date.now();
  const aggregatedData = [];

  // Group data by timeframe intervals
  const groupedData = new Map<number, any[]>();

  data.forEach((item) => {
    const intervalTime = Math.floor(item.timestamp / interval) * interval;
    if (!groupedData.has(intervalTime)) {
      groupedData.set(intervalTime, []);
    }
    groupedData.get(intervalTime)!.push(item);
  });

  // Convert grouped data to candlestick format
  const sortedIntervals = Array.from(groupedData.keys()).sort((a, b) => b - a);

  for (let i = 0; i < Math.min(sortedIntervals.length, limit); i++) {
    const intervalTime = sortedIntervals[i];
    const intervalData = groupedData.get(intervalTime)!;

    if (intervalData.length > 0) {
      const prices = intervalData.map((d) => d.price);
      const open = prices[0];
      const close = prices[prices.length - 1];
      const high = Math.max(...prices);
      const low = Math.min(...prices);

      aggregatedData.push({
        time: Math.floor(intervalTime / 1000), // Convert to seconds for Lightweight Charts
        open,
        high,
        low,
        close,
        timestamp: intervalTime,
        volume: intervalData.length, // Use data point count as volume proxy
      });
    }
  }

  return aggregatedData.reverse(); // Return in chronological order
}

// Start hermes connection (singleton)
let hermesStream: any = null;

async function startHermesConnection() {
  if (hermesStream) return;

  try {
    const priceIds = MarketList.map((spot) => spot.id);
    hermesStream = await hermesConnection.getPriceUpdatesStream(priceIds);

    hermesStream.onmessage = (event: any) => {
      try {
        const data = JSON.parse(event.data);
        const parsedPrices = parsePriceData(data);

        // Store latest prices
        parsedPrices.forEach((price: any) => {
          priceData.set(price.id, price);

          // Add to historical data for each timeframe
          Object.keys(TIMEFRAME_INTERVALS).forEach((timeframe) => {
            if (!historicalData.has(price.id)) {
              historicalData.set(price.id, new Map());
            }
            if (!historicalData.get(price.id)!.has(timeframe)) {
              historicalData.get(price.id)!.set(timeframe, []);
            }

            const timeframeData = historicalData.get(price.id)!.get(timeframe)!;
            timeframeData.push(price);

            // Keep only last 200 data points per timeframe
            if (timeframeData.length > 200) {
              timeframeData.shift();
            }
          });
        });

        // Send to all connected clients
        const message = `data: ${JSON.stringify(parsedPrices)}\n\n`;
        connections.forEach((controller) => {
          try {
            controller.enqueue(new TextEncoder().encode(message));
          } catch (error) {
            console.error("Error sending to client:", error);
          }
        });

        console.log("Broadcasted price update to", connections.size, "clients");
      } catch (error) {
        console.error("Error parsing price data:", error);
      }
    };

    hermesStream.onerror = (error: any) => {
      console.error("Hermes stream error:", error);
      hermesStream = null;
    };

    console.log("Hermes connection started");
  } catch (error) {
    console.error("Error starting hermes connection:", error);
  }
}

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const marketId = searchParams.get("marketId");
  const timeframe = searchParams.get("timeframe") || "1h";

  if (!marketId) {
    return NextResponse.json({ error: "Market ID required" }, { status: 400 });
  }

  // Start hermes connection if not already started
  await startHermesConnection();

  // Create SSE stream
  const stream = new ReadableStream({
    start(controller) {
      // Add client to connections
      const clientId = Math.random().toString(36).substring(7);
      connections.set(clientId, controller);

      // Send initial data if available
      const marketHistoricalData = historicalData.get(marketId);
      if (marketHistoricalData && marketHistoricalData.has(timeframe)) {
        const timeframeData = marketHistoricalData.get(timeframe)!;
        const aggregatedData = aggregateDataForTimeframe(
          timeframeData,
          timeframe,
          100
        );

        if (aggregatedData.length > 0) {
          const message = `data: ${JSON.stringify({
            type: "historical",
            data: aggregatedData,
          })}\n\n`;
          controller.enqueue(new TextEncoder().encode(message));
        }
      }

      // Send ping every 30 seconds to keep connection alive
      const pingInterval = setInterval(() => {
        try {
          controller.enqueue(
            new TextEncoder().encode('data: {"type": "ping"}\n\n')
          );
        } catch (error) {
          clearInterval(pingInterval);
          connections.delete(clientId);
        }
      }, 30000);

      // Cleanup on close
      request.signal.addEventListener("abort", () => {
        clearInterval(pingInterval);
        connections.delete(clientId);
        console.log("Client disconnected:", clientId);
      });
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Cache-Control",
    },
  });
}

// Get historical data for specific timeframe
export async function POST(request: NextRequest) {
  try {
    const { marketId, timeframe = "1h", limit = 100 } = await request.json();

    if (!marketId) {
      return NextResponse.json(
        { error: "Market ID required" },
        { status: 400 }
      );
    }

    // Get historical data for the market and timeframe
    const marketHistoricalData = historicalData.get(marketId);
    if (!marketHistoricalData || !marketHistoricalData.has(timeframe)) {
      return NextResponse.json(
        { error: "No historical data available for this market and timeframe" },
        { status: 404 }
      );
    }

    const timeframeData = marketHistoricalData.get(timeframe)!;
    const aggregatedData = aggregateDataForTimeframe(
      timeframeData,
      timeframe,
      limit
    );

    return NextResponse.json({
      marketId,
      timeframe,
      data: aggregatedData,
      lastUpdate: Date.now(),
    });
  } catch (error) {
    console.error("Error getting historical data:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
