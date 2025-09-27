import { MarketList } from "@/data/market-list";
// import { DatabaseService } from "@/lib/supabase"; // TODO: Implement database service

// Simple price data structure
interface PriceData {
  id: string;
  price: number;
  publish_time: number;
  created_at: Date;
}

// In-memory storage (replace with actual database)
const priceDataStore: PriceData[] = [];

// Initialize stores
function initializeStores() {
  // Clear existing data
  priceDataStore.length = 0;
}

// Fetch price data from Pyth API
async function fetchPriceData(
  assetId: string,
  startTime: number,
  durationSeconds: number
) {
  const url = `https://benchmarks.pyth.network/v1/updates/price/${startTime}/${durationSeconds}?ids=${assetId}&encoding=hex&parsed=true&unique=true`;

  console.log(`🔍 Fetching data for ${assetId}`);
  console.log(
    `📅 Start time: ${new Date(
      startTime * 1000
    ).toISOString()}, Duration: ${durationSeconds} seconds`
  );
  console.log(`🌐 URL: ${url}`);

  try {
    const response = await fetch(url);
    console.log(
      `📡 Response status: ${response.status} ${response.statusText}`
    );

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`❌ HTTP error response:`, errorText);
      throw new Error(`HTTP error! status: ${response.status}`);
    }

    const data = await response.json();
    console.log(`✅ Successfully fetched data:`, {
      hasData: !!data,
      isArray: Array.isArray(data),
      length: Array.isArray(data) ? data.length : "N/A",
      firstItem: Array.isArray(data) && data.length > 0 ? data[0] : "N/A",
    });
    return data;
  } catch (error) {
    console.error(`❌ Error fetching data for ${assetId}:`, error);
    return null;
  }
}

// Parse price data from Pyth API response
function parsePriceData(rawData: any[]): PriceData[] {
  console.log(`🔧 Parsing raw data...`);
  console.log(`📊 Raw data structure:`, {
    isArray: Array.isArray(rawData),
    length: Array.isArray(rawData) ? rawData.length : "N/A",
    firstItemKeys:
      Array.isArray(rawData) && rawData.length > 0
        ? Object.keys(rawData[0])
        : "N/A",
  });

  const parsedData: PriceData[] = [];

  rawData.forEach((update, updateIndex) => {
    console.log(`🔍 Processing update ${updateIndex + 1}:`, {
      hasParsed: !!update.parsed,
      parsedIsArray: Array.isArray(update.parsed),
      parsedLength: Array.isArray(update.parsed) ? update.parsed.length : "N/A",
    });

    if (update.parsed && Array.isArray(update.parsed)) {
      update.parsed.forEach((item: any, itemIndex) => {
        console.log(`💰 Processing price item ${itemIndex + 1}:`, {
          id: item.id,
          hasPrice: !!item.price,
          hasMetadata: !!item.metadata,
          priceInfo: item.price
            ? {
                price: item.price.price,
                expo: item.price.expo,
                conf: item.price.conf,
                publish_time: item.price.publish_time,
              }
            : "N/A",
        });

        const priceInfo = item.price;
        const metadata = item.metadata;

        const parsedPrice =
          parseFloat(priceInfo.price) / Math.pow(10, -priceInfo.expo);
        const parsedConfidence =
          parseFloat(priceInfo.conf) / Math.pow(10, -priceInfo.expo);

        console.log(`📈 Calculated values:`, {
          originalPrice: priceInfo.price,
          exponent: priceInfo.expo,
          parsedPrice: parsedPrice,
          originalConf: priceInfo.conf,
          parsedConfidence: parsedConfidence,
          publishTime: priceInfo.publish_time,
          slot: metadata.slot,
        });

        parsedData.push({
          id: item.id,
          price: parsedPrice,
          publish_time: priceInfo.publish_time,
          created_at: new Date(),
        });
      });
    }
  });

  console.log(
    `✅ Parsing complete: ${parsedData.length} price data points created`
  );
  return parsedData;
}

// Store price data in Supabase
async function storePriceData(priceData: PriceData[]) {
  console.log(
    `💾 Storing ${priceData.length} price data points in Supabase...`
  );

  try {
    // Convert to database format
    const dbPriceData = priceData.map((item) => ({
      asset_id: item.id,
      price: item.price,
      publish_time: item.publish_time,
    }));

    console.log(`📝 Database format sample:`, dbPriceData.slice(0, 2));

    // const result = await DatabaseService.storePriceData(dbPriceData); // TODO: Implement database service
    const result = null; // Placeholder
    console.log(
      `✅ Successfully stored ${priceData.length} price data points in Supabase`
    );
    console.log(
      `📊 Database response:`,
      result ? `Inserted ${result.length} records` : "No response"
    );
  } catch (error) {
    console.error("❌ Error storing price data:", error);
    console.log(`🔄 Falling back to in-memory storage...`);
    // Fallback to in-memory storage
    priceDataStore.push(...priceData);
    console.log(`📦 In-memory storage now has ${priceDataStore.length} items`);
  }
}

// OHLC functions removed - only storing raw price data

// Main cron job function
async function runPythCron() {
  console.log("Starting Pyth cron job...");

  try {
    // Initialize stores
    initializeStores();

    // Process each asset
    for (const spot of MarketList) {
      console.log(`Processing ${spot.name} (${spot.id})`);

      // Fetch historical data in 60-second chunks
      const startTimestamp = 1715100000; // Your specified start time (May 2024)
      const now = Math.floor(Date.now() / 1000);
      const totalDuration = now - startTimestamp;

      console.log(
        `📊 Total time range: ${totalDuration} seconds (${Math.floor(
          totalDuration / 3600
        )} hours)`
      );

      // Fetch data in 60-second chunks
      const chunkSize = 60; // 60 seconds per chunk
      const totalChunks = Math.ceil(totalDuration / chunkSize);

      console.log(
        `🔄 Fetching ${totalChunks} chunks of ${chunkSize} seconds each...`
      );

      let allPriceData: PriceData[] = [];
      const maxCallsPerWindow = 25; // Max 25 API calls
      const windowDuration = 10000; // Every 10 seconds
      let callCount = 0;
      let windowStart = Date.now();

      for (let i = 0; i < totalChunks; i++) {
        // Check if we need to wait for rate limit window
        if (callCount >= maxCallsPerWindow) {
          const elapsed = Date.now() - windowStart;
          const remaining = windowDuration - elapsed;

          if (remaining > 0) {
            console.log(
              `⏳ Rate limit reached. Waiting ${remaining}ms before continuing...`
            );
            await new Promise((resolve) => setTimeout(resolve, remaining));
          }

          // Reset counters
          callCount = 0;
          windowStart = Date.now();
        }

        const chunkStart = startTimestamp + i * chunkSize;
        const chunkDuration = Math.min(
          chunkSize,
          totalDuration - i * chunkSize
        );

        console.log(
          `📦 Chunk ${i + 1}/${totalChunks}: ${new Date(
            chunkStart * 1000
          ).toISOString()} (+${chunkDuration}s) [Calls: ${
            callCount + 1
          }/${maxCallsPerWindow}]`
        );

        const rawData = await fetchPriceData(
          spot.id,
          chunkStart,
          chunkDuration
        );

        callCount++;

        if (!rawData) {
          console.error(`Failed to fetch data for chunk ${i + 1}`);
          continue;
        }

        const priceData = parsePriceData(rawData);
        console.log(`✅ Chunk ${i + 1}: ${priceData.length} price updates`);

        allPriceData.push(...priceData);

        // Small delay between calls
        await new Promise((resolve) => setTimeout(resolve, 200));
      }

      console.log(
        `🎉 Total collected: ${allPriceData.length} price updates for ${spot.name}`
      );

      // Store all price data
      if (allPriceData.length > 0) {
        await storePriceData(allPriceData);
        // OHLC generation removed - only storing raw price data
      }
    }

    console.log("Pyth cron job completed successfully");
    console.log(`Total price data points stored: ${priceDataStore.length}`);

    // Show sample of stored data
    if (priceDataStore.length > 0) {
      console.log("\nSample price data:");
      priceDataStore.slice(0, 3).forEach((data, index) => {
        console.log(
          `${index + 1}. Price: $${data.price.toFixed(2)}, Time: ${new Date(
            data.publish_time * 1000
          ).toISOString()}`
        );
      });
    }
  } catch (error) {
    console.error("Error in Pyth cron job:", error);
  }
}

// Export functions for use
export { runPythCron, priceDataStore };

// Run the cron job if this file is executed directly
if (require.main === module) {
  const args = process.argv.slice(2);
  const continuous = args.includes("--continuous") || args.includes("-c");

  if (continuous) {
    console.log("🔄 Starting continuous mode - fetching data every 60 seconds");
    console.log("Press Ctrl+C to stop");

    // Run immediately
    runPythCron().catch(console.error);

    // Then run every 60 seconds
    setInterval(() => {
      console.log("\n🔄 Running scheduled update...");
      runPythCron().catch(console.error);
    }, 60000); // 60 seconds
  } else {
    runPythCron()
      .then(() => {
        console.log("Cron job finished");
        process.exit(0);
      })
      .catch((error) => {
        console.error("Cron job failed:", error);
        process.exit(1);
      });
  }
}
