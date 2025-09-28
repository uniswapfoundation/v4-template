import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain, encodeAbiParameters, keccak256 } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

// Pyth ETH/USD price feed ID
const PYTH_ETH_USD_FEED_ID = '0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace';

// Function to fetch real-time ETH price from Pyth
async function fetchPythPrice(): Promise<number> {
  try {
    const response = await fetch(`https://hermes.pyth.network/api/latest_price_feeds?ids[]=${PYTH_ETH_USD_FEED_ID}`);
    const data = await response.json();
    
    if (data && data.length > 0) {
      const priceData = data[0].price;
      const price = parseInt(priceData.price);
      const expo = priceData.expo;
      const actualPrice = price * Math.pow(10, expo);
      
      console.log('📡 Pyth Network Price Feed:');
      console.log('  Raw Price:', price);
      console.log('  Exponent:', expo);
      console.log('  Actual ETH Price:', actualPrice.toFixed(2), 'USD');
      console.log('  Confidence:', parseInt(data[0].price.conf) * Math.pow(10, expo));
      console.log('  Publish Time:', new Date(data[0].price.publish_time * 1000).toISOString());
      
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

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

const account = privateKeyToAccount(PK as `0x${string}`);

const unichain = defineChain({
  id: CHAIN_ID,
  name: 'Unichain Sepolia',
  network: 'unichain-sepolia',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] }, public: { http: [RPC_URL] } },
  blockExplorers: { default: { name: 'Uniscan', url: 'https://sepolia.uniscan.xyz' } },
});

const walletClient = createWalletClient({
  account,
  chain: unichain,
  transport: http(RPC_URL),
});

const publicClient = createPublicClient({
  chain: unichain,
  transport: http(RPC_URL),
});

// Get command line arguments
const args = process.argv.slice(2);
if (args.length < 1) {
  console.log('Usage: bun run closePositionWithPyth.ts <tokenId> [percentToClose]');
  console.log('Examples:');
  console.log('  bun run closePositionWithPyth.ts 5           # Close 100% of position #5');
  console.log('  bun run closePositionWithPyth.ts 3 50        # Close 50% of position #3');
  console.log('  bun run closePositionWithPyth.ts 7 25        # Close 25% of position #7');
  process.exit(1);
}

const tokenId = parseInt(args[0]!);
const percentToClose = args[1] ? parseFloat(args[1]) : 100;

// Validate inputs
if (isNaN(tokenId) || tokenId <= 0) {
  console.error('❌ Invalid token ID. Must be a positive number.');
  process.exit(1);
}

if (isNaN(percentToClose) || percentToClose <= 0 || percentToClose > 100) {
  console.error('❌ Invalid percentage. Must be between 1 and 100.');
  process.exit(1);
}

async function closePositionWithPyth() {
  try {
    console.log('🔄 Closing Position with Real-Time Pyth Pricing');
    console.log('👤 Using account:', account.address);
    console.log('📊 Position ID:', tokenId);
    console.log('📈 Percentage to close:', percentToClose + '%');

    const c = getContracts();
    
    // Generate pool ID
    const poolId = keccak256(
      encodeAbiParameters(
        [
          { name: 'currency0', type: 'address' },
          { name: 'currency1', type: 'address' },
          { name: 'fee', type: 'uint24' },
          { name: 'tickSpacing', type: 'int24' },
          { name: 'hooks', type: 'address' }
        ],
        [
          c.mockVETH.address as `0x${string}`,
          c.mockUSDC.address as `0x${string}`,
          3000,
          60,
          c.perpsHook.address as `0x${string}`
        ]
      )
    );

    console.log('🆔 Pool ID:', poolId);

    // Fetch real-time ETH price from Pyth
    const pythPrice = await fetchPythPrice();

    // Get current position details
    console.log('📊 Fetching position details...');
    const position = await publicClient.readContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi as any,
      functionName: 'getPosition',
      args: [tokenId]
    }) as any;

    if (!position || position.sizeBase === 0n) {
      console.error('❌ Position not found or already closed');
      process.exit(1);
    }

    const isLong = position.sizeBase > 0n;
    const positionSize = isLong ? position.sizeBase : -position.sizeBase;
    const entryPrice = Number(position.entryPrice) / 1e18;
    const margin = Number(position.margin) / 1e6;

    console.log('📋 Position Details:');
    console.log('  Type:', isLong ? 'LONG' : 'SHORT');
    console.log('  Size:', Number(positionSize) / 1e18, 'VETH');
    console.log('  Entry Price:', entryPrice.toFixed(2), 'USD');
    console.log('  Margin:', margin, 'USDC');
    console.log('  Current Price:', pythPrice.toFixed(2), 'USD (from Pyth)');

    // Calculate PnL
    const notionalValue = (Number(positionSize) / 1e18) * pythPrice;
    const entryNotional = (Number(positionSize) / 1e18) * entryPrice;
    const unrealizedPnL = isLong ? (notionalValue - entryNotional) : (entryNotional - notionalValue);
    const pnlPercent = (unrealizedPnL / margin) * 100;

    console.log('💰 Current PnL:');
    console.log('  Unrealized PnL:', unrealizedPnL.toFixed(2), 'USDC');
    console.log('  PnL Percentage:', pnlPercent.toFixed(2) + '%');
    console.log('  Current Notional:', notionalValue.toFixed(2), 'USDC');

    // Calculate size to close
    const sizeToClose = percentToClose === 100 ? 
      positionSize : 
      (positionSize * BigInt(Math.floor(percentToClose * 100))) / 10000n;

    const partialPnL = percentToClose === 100 ? 
      unrealizedPnL : 
      (unrealizedPnL * percentToClose / 100);

    console.log('📊 Closing Details:');
    console.log('  Size to close:', Number(sizeToClose) / 1e18, 'VETH');
    console.log('  Expected PnL from closure:', partialPnL.toFixed(2), 'USDC');

    // Get current mark price from hook
    const currentMarkPrice = await publicClient.readContract({
      address: c.perpsHook.address,
      abi: c.perpsHook.abi as any,
      functionName: 'getMarkPrice',
      args: [poolId]
    }) as bigint;

    console.log('📊 Current Mark Price:', Number(currentMarkPrice) / 1e18, 'USD');

    // Close the position
    console.log('🔄 Closing position...');
    
    let closeTx;
    if (percentToClose === 100) {
      // Close entire position
      closeTx = await walletClient.writeContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: 'closePosition',
        args: [tokenId, currentMarkPrice]
      });
    } else {
      // Partial close - reduce position size using updatePosition
      const newSize = positionSize - sizeToClose;
      const adjustedSize = isLong ? newSize : -newSize;
      const currentMargin = Number(position.margin); // Keep current margin
      
      closeTx = await walletClient.writeContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: 'updatePosition',
        args: [tokenId, adjustedSize, currentMargin]
      });
    }

    console.log('⏳ Waiting for position closure...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash: closeTx });

    console.log('🎉 Position closed successfully!');
    console.log('📋 Transaction Hash:', closeTx);
    console.log('📦 Block Number:', receipt.blockNumber);

    // Rebalance the pool using the hook after closing the position
    console.log('⚖️ Rebalancing virtual reserves using real-time Pyth price after closure...');
    
    try {
      // Get current virtual reserves
      const marketStateBefore = await publicClient.readContract({
        address: c.perpsHook.address,
        abi: c.perpsHook.abi as any,
        functionName: 'getMarketState',
        args: [poolId]
      }) as any;
      
      console.log('📊 Virtual reserves before rebalancing:');
      console.log('  Virtual Base:', Number(marketStateBefore.virtualBase) / 1e18, 'VETH');
      console.log('  Virtual Quote:', Number(marketStateBefore.virtualQuote) / 1e6, 'USDC');
      console.log('  Current Mark Price:', Number(marketStateBefore.virtualQuote) * 1e30 / Number(marketStateBefore.virtualBase) / 1e18, 'USD/VETH');
      
      // Rebalance to match real Pyth price with optimal liquidity
      const targetPrice = pythPrice; // Use real Pyth price
      const newVirtualQuote = 1200000000000n; // 1.2M USDC (optimal liquidity)
      const newVirtualBase = newVirtualQuote * 1000000000000000000n / BigInt(Math.floor(targetPrice * 1e6)); // Calculate base for real price
      
      console.log('🎯 Target rebalancing (using Pyth price after closure):');
      console.log('  New Virtual Base:', Number(newVirtualBase) / 1e18, 'VETH');
      console.log('  New Virtual Quote:', Number(newVirtualQuote) / 1e6, 'USDC');
      console.log('  Target Price:', targetPrice.toFixed(2), 'USD/VETH (from Pyth)');
      
      const rebalanceTx = await walletClient.writeContract({
        address: c.perpsHook.address,
        abi: c.perpsHook.abi as any,
        functionName: 'emergencyRebalanceVAMM',
        args: [poolId, newVirtualBase, newVirtualQuote]
      });
      
      console.log('✅ Virtual reserves rebalanced successfully after closure!');
      console.log('📋 Rebalance Transaction Hash:', rebalanceTx);
      
      // Verify the rebalancing
      const marketStateAfter = await publicClient.readContract({
        address: c.perpsHook.address,
        abi: c.perpsHook.abi as any,
        functionName: 'getMarketState',
        args: [poolId]
      }) as any;
      
      console.log('📊 Virtual reserves after rebalancing:');
      console.log('  Virtual Base:', Number(marketStateAfter.virtualBase) / 1e18, 'VETH');
      console.log('  Virtual Quote:', Number(marketStateAfter.virtualQuote) / 1e6, 'USDC');
      console.log('  New Mark Price:', Number(marketStateAfter.virtualQuote) * 1e30 / Number(marketStateAfter.virtualBase) / 1e18, 'USD/VETH');
      
    } catch (rebalanceError) {
      console.error('⚠️ Rebalancing failed (position still closed successfully):', rebalanceError);
    }

    // Show transaction details
    const logs = receipt.logs;
    console.log('📊 Transaction produced', logs.length, 'events');

    console.log('\n📊 Closure Summary:');
    console.log('  Position ID:', tokenId);
    console.log('  Type:', isLong ? 'LONG' : 'SHORT');
    console.log('  Percentage Closed:', percentToClose + '%');
    console.log('  Size Closed:', Number(sizeToClose) / 1e18, 'VETH');
    console.log('  Entry Price:', entryPrice.toFixed(2), 'USD');
    console.log('  Exit Price:', pythPrice.toFixed(2), 'USD (Pyth)');
    console.log('  Realized PnL:', partialPnL.toFixed(2), 'USDC');
    
    console.log('\n💡 Next Steps:');
    console.log('  📊 Check remaining positions: bun run portfolioOverviewFixed.ts');
    console.log('  📊 View specific position: bun run showPositions.ts', tokenId);
    console.log('  💰 Check balances: bun run quickPortfolio.ts');

  } catch (error) {
    console.error('❌ Error:', error);
  }
}

closePositionWithPyth().catch(console.error);
