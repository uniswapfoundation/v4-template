import 'dotenv/config';

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
import { http, createWalletClient, createPublicClient, defineChain, keccak256, encodeAbiParameters } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

// Get command line arguments
const args = process.argv.slice(2);
if (args.length < 2) {
  console.log('Usage: bun run openShortCorrectCalculation.ts <marginUSDC> <leverage>');
  console.log('Example: bun run openShortCorrectCalculation.ts 100 5  # 100 USDC margin at 5x leverage');
  process.exit(1);
}

const marginUSDC = parseFloat(args[0]!);
const leverage = parseFloat(args[1]!);

async function openShortCorrectCalculation() {
  console.log('🔄 Opening Short Position with Correct Calculations');
  
  const account = privateKeyToAccount(PK as `0x${string}`);
  const chain = defineChain({ 
    id: CHAIN_ID, 
    name: 'UnichainSepolia', 
    nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 }, 
    rpcUrls: { 
      default: { http: [RPC_URL] }, 
      public: { http: [RPC_URL] } 
    } 
  });
  
  const transport = http(RPC_URL);
  const publicClient = createPublicClient({ transport, chain });
  const walletClient = createWalletClient({ account, transport, chain });
  const c = getContracts(CHAIN_ID);

  console.log('👤 Using account:', account.address);

  try {
    // Setup pool configuration (same as working scripts)
    const fee = 3000; // 0.3%
    const tickSpacing = 60;
    const hooks = c.perpsHook.address;
    
    console.log('💱 Pool Configuration:');
    console.log('  Currency0:', c.mockVETH.address);
    console.log('  Currency1:', c.mockUSDC.address);
    console.log('  Fee:', fee, 'bps');
    console.log('  Hook:', hooks);

    // Calculate poolId (same method as working scripts)
    const poolKey = encodeAbiParameters(
      [
        { name: 'currency0', type: 'address' },
        { name: 'currency1', type: 'address' },
        { name: 'fee', type: 'uint24' },
        { name: 'tickSpacing', type: 'int24' },
        { name: 'hooks', type: 'address' }
      ],
      [c.mockVETH.address, c.mockUSDC.address, fee, tickSpacing, hooks]
    );
    
    const poolId = keccak256(poolKey);
    console.log('🆔 Pool ID:', poolId);
    
    console.log('📊 Position Parameters:');
    console.log('  Margin:', marginUSDC, 'USDC');
    console.log('  Leverage:', leverage, 'x');

    // Get current mark price for calculations
    const markPrice = await publicClient.readContract({
      address: c.fundingOracle.address,
      abi: c.fundingOracle.abi as any,
      functionName: 'getMarkPrice',
      args: [poolId]
    }) as bigint;
    
    console.log('📊 Current Mark Price:', Number(markPrice) / 1e18, 'USDC per VETH');

    // Calculate position size correctly for SHORT
    // For SHORT: negative sizeBase indicates short position
    const notionalValueUSDC = marginUSDC * leverage; // e.g., 100 * 5 = 500 USDC
    const priceUSDCPerVETH = Number(markPrice) / 1e18; // e.g., 2000 USDC per VETH
    const positionSizeVETH = notionalValueUSDC / priceUSDCPerVETH; // e.g., 500 / 2000 = 0.25 VETH
    
    // Convert to contract units
    const marginAmountWei = BigInt(Math.floor(marginUSDC * 1e6)); // USDC has 6 decimals
    const positionSizeWei = -BigInt(Math.floor(positionSizeVETH * 1e18)); // NEGATIVE for SHORT position
    
    console.log('📉 Expected Position Size:', -positionSizeVETH, 'VETH (SHORT)');
    console.log('💵 Expected Notional Value:', notionalValueUSDC, 'USDC');
    console.log('🔢 Position Size Wei:', positionSizeWei.toString());
    console.log('🔢 Margin Wei:', marginAmountWei.toString());

    // Check USDC balance
    const usdcBalance = await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    }) as bigint;
    
    console.log('💳 Current USDC Balance:', Number(usdcBalance) / 1e6);
    
    if (usdcBalance < marginAmountWei) {
      throw new Error(`Insufficient USDC balance. Need ${marginUSDC} USDC, have ${Number(usdcBalance) / 1e6} USDC`);
    }

    // Step 1: Deposit margin to MarginAccount (following working pattern)
    console.log('💰 Depositing margin to MarginAccount for positioning...');
    
    // Approve USDC for MarginAccount
    const approveTx = await walletClient.writeContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'approve',
      args: [c.marginAccount.address, marginAmountWei]
    });
    await publicClient.waitForTransactionReceipt({ hash: approveTx });
    console.log('✅ USDC approved for MarginAccount');
    
    // Deposit to MarginAccount
    const depositTx = await walletClient.writeContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'deposit',
      args: [marginAmountWei]
    });
    await publicClient.waitForTransactionReceipt({ hash: depositTx });
    console.log('✅ Margin deposited to MarginAccount');

    // Step 2: Open SHORT position via PositionManager
    console.log('🔄 Opening SHORT position via PositionManager...');
    
    const marketId = poolId;
    const sizeBase = positionSizeWei; // NEGATIVE for short position
    const entryPrice = markPrice;
    const margin = marginAmountWei;
    
    console.log('📋 Position Manager Parameters:');
    console.log('  Market ID:', marketId);
    console.log('  Size Base:', sizeBase.toString(), '(negative = SHORT)');
    console.log('  Entry Price:', entryPrice.toString());
    console.log('  Margin:', margin.toString());

    const openPositionTx = await walletClient.writeContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi as any,
      functionName: 'openPosition',
      args: [marketId, sizeBase, entryPrice, margin]
    });
    
    console.log('⏳ Waiting for position creation...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash: openPositionTx });
    
    console.log('🎉 SHORT Position opened successfully!');
    console.log('📋 Transaction Hash:', openPositionTx);
    console.log('📦 Block Number:', receipt.blockNumber);
    
    // Show transaction details
    const logs = receipt.logs;
    console.log('📊 Transaction produced', logs.length, 'events');

    // Rebalance the pool using the hook after opening the SHORT position
    console.log('⚖️ Rebalancing virtual reserves using real-time Pyth price after SHORT...');
    
    try {
      // Fetch real-time ETH price from Pyth
      const pythPrice = await fetchPythPrice();
      
      // Get current virtual reserves to see the impact
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
      
      // Rebalance to match real Pyth price with increased liquidity
      // After a SHORT position, we want to add more virtual liquidity to stabilize the price
      // For shorts, we might want to adjust the reserves differently than longs
      const targetPrice = pythPrice; // Use real Pyth price
      const newVirtualQuote = 1200000000000n; // 1.2M USDC (increased from 1M)
      const newVirtualBase = newVirtualQuote * 1000000000000000000n / BigInt(Math.floor(targetPrice * 1e6)); // Calculate base for real price
      
      console.log('🎯 Target rebalancing (SHORT position using Pyth price):');
      console.log('  New Virtual Base:', Number(newVirtualBase) / 1e18, 'VETH');
      console.log('  New Virtual Quote:', Number(newVirtualQuote) / 1e6, 'USDC');
      console.log('  Target Price:', targetPrice.toFixed(2), 'USD/VETH (from Pyth)');
      
      const rebalanceTx = await walletClient.writeContract({
        address: c.perpsHook.address,
        abi: c.perpsHook.abi as any,
        functionName: 'emergencyRebalanceVAMM',
        args: [poolId, newVirtualBase, newVirtualQuote]
      });
      
      await publicClient.waitForTransactionReceipt({ hash: rebalanceTx });
      console.log('✅ Virtual reserves rebalanced successfully after SHORT!');
      console.log('📋 Rebalance Transaction Hash:', rebalanceTx);
      
      // Verify the new state
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
      console.error('⚠️ Rebalancing failed:', rebalanceError);
      console.log('ℹ️ SHORT position was opened successfully, but rebalancing encountered an issue');
    }
    
    console.log('\n📊 Position Summary:');
    console.log('  Type: SHORT');
    console.log('  Size:', Math.abs(positionSizeVETH).toFixed(4), 'VETH');
    console.log('  Margin:', marginUSDC, 'USDC');
    console.log('  Leverage:', leverage + 'x');
    console.log('  Entry Price:', priceUSDCPerVETH, 'USDC per VETH');
    console.log('  Notional Value:', notionalValueUSDC, 'USDC');
    
    console.log('\n💡 Next Steps:');
    console.log('  📊 Check position: bun run showPositions.ts <tokenId>');
    console.log('  📊 Portfolio overview: bun run quickPortfolio.ts');

  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  }
}

openShortCorrectCalculation().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
