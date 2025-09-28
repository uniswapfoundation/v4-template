import 'dotenv/config';

// Pyth ETH/USD price feed ID
const PYTH_ETH_USD_FEED_ID = '0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace';

// Function to fetch real-time ETH price from Pyth
async function fetchPythPrice(): Promise<number> {
  try {
    console.log('🔍 Fetching ETH price from Pyth Network...');
    const response = await fetch(`https://hermes.pyth.network/api/latest_price_feeds?ids[]=${PYTH_ETH_USD_FEED_ID}`);
    const data = await response.json();
    
    if (data && data.length > 0) {
      const priceData = data[0].price;
      const price = parseInt(priceData.price);
      const expo = priceData.expo;
      const actualPrice = price * Math.pow(10, expo);
      
      console.log('📡 Pyth Network Price Feed:');
      console.log('  Feed ID:', PYTH_ETH_USD_FEED_ID);
      console.log('  Raw Price:', price);
      console.log('  Exponent:', expo);
      console.log('  Actual ETH Price:', actualPrice.toFixed(2), 'USD');
      console.log('  Confidence:', parseInt(data[0].price.conf) * Math.pow(10, expo));
      console.log('  Publish Time:', new Date(data[0].price.publish_time * 1000).toISOString());
      console.log('  EMA Price:', parseInt(data[0].ema_price.price) * Math.pow(10, data[0].ema_price.expo));
      
      return actualPrice;
    } else {
      throw new Error('No price data received from Pyth');
    }
  } catch (error) {
    console.error('❌ Failed to fetch Pyth price:', error);
    console.log('🔄 Falling back to default price of $2000');
    return 2000; // Fallback price
  }
}

// Test the function
async function main() {
  console.log('🧪 Testing Pyth Price Feed Integration\n');
  
  const price = await fetchPythPrice();
  
  console.log('\n✅ Price fetch completed!');
  console.log('💰 Current ETH Price:', price.toFixed(2), 'USD');
  
  // Calculate virtual reserves for different liquidity levels
  console.log('\n📊 Virtual Reserve Calculations:');
  
  const liquidityLevels = [500000, 1000000, 1500000]; // 500K, 1M, 1.5M USDC
  
  for (const liquidity of liquidityLevels) {
    const virtualQuote = liquidity * 1e6; // Convert to 6 decimals
    const virtualBase = (liquidity * 1e18) / price; // Calculate base for real price
    
    console.log(`\n  ${liquidity/1000}K USDC Liquidity:`);
    console.log(`    Virtual Quote: ${liquidity} USDC`);
    console.log(`    Virtual Base: ${(virtualBase / 1e18).toFixed(4)} VETH`);
    console.log(`    Calculated Price: ${((virtualQuote * 1e30) / virtualBase / 1e18).toFixed(2)} USD/VETH`);
  }
}

main().catch(console.error);
