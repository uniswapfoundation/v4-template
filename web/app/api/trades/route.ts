import { NextRequest, NextResponse } from "next/server";
import fs from "fs";
import path from "path";

// GET /api/trades - Get trades with short and long format
export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const marketId = searchParams.get("marketId");
    const timeframe = searchParams.get("timeframe") || "1h";

    if (!marketId) {
      return NextResponse.json(
        { error: "Market ID is required" },
        { status: 400 }
      );
    }

    // Read dummy data from JSON file
    const dataPath = path.join(process.cwd(), "backend", "data", "trades.json");
    const fileContents = fs.readFileSync(dataPath, "utf8");
    const allTrades = JSON.parse(fileContents);

    // Get trades for specific market
    const marketTrades = allTrades[marketId] || { short: [], long: [] };

    return NextResponse.json({
      success: true,
      data: marketTrades,
      marketId,
      timeframe,
      message: "Trades retrieved successfully",
    });
  } catch (error) {
    console.error("Error fetching trades:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}

// POST /api/trades - Create a new trade
export async function POST(request: NextRequest) {
  try {
    const body = await request.json();

    // TODO: Implement logic to create a new trade
    // Validate required fields: market, side, size, price, etc.

    return NextResponse.json({
      success: true,
      data: {
        id: "generated-id",
        ...body,
      },
      message: "Trade created successfully",
    });
  } catch (error) {
    console.error("Error creating trade:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
