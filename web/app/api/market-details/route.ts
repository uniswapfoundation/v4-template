import { NextRequest, NextResponse } from "next/server";
import fs from "fs";
import path from "path";

// GET /api/market-details - Get market details
export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const marketId = searchParams.get("marketId");

    if (!marketId) {
      return NextResponse.json(
        { error: "Market ID is required" },
        { status: 400 }
      );
    }

    // Read dummy data from JSON file
    const dataPath = path.join(
      process.cwd(),
      "backend",
      "data",
      "market-details.json"
    );
    const fileContents = fs.readFileSync(dataPath, "utf8");
    const allMarkets = JSON.parse(fileContents);

    // Get market details for specific market
    const marketDetails = allMarkets[marketId];

    if (!marketDetails) {
      return NextResponse.json({ error: "Market not found" }, { status: 404 });
    }

    return NextResponse.json({
      success: true,
      data: marketDetails,
      message: "Market details retrieved successfully",
    });
  } catch (error) {
    console.error("Error fetching market details:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
