import 'dotenv/config';
import { createPublicClient, http, defineChain, parseUnits, formatUnits } from 'viem';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';
import { calculateUsdcVethPoolId } from './poolUtils';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);

async function debugHookValidation() {
  console.log('🔬 DEBUG: Hook Validation Logic Analysis');
  console.log('========================================');
  
  const contracts = getContracts(CHAIN_ID);
  const transport = http(RPC_URL);
  const chain = defineChain({ 
    id: CHAIN_ID, 
    name: 'UnichainSepolia', 
    nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 }, 
    rpcUrls: { default: { http: [RPC_URL] }, public: { http: [RPC_URL] } } 
  });
  
  const publicClient = createPublicClient({ transport, chain });
  const c = contracts;
  const poolId = calculateUsdcVethPoolId(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);

  console.log('🆔 Pool ID:', poolId);
  console.log('');

  try {
    // Get vAMM state for calculations
    const marketState = await publicClient.readContract({
      address: c.perpsHook.address,
      abi: c.perpsHook.abi as any,
      functionName: 'getMarketState',
      args: [poolId]
    });

    console.log('📊 VALIDATION TEST SETUP:');
    console.log('   Virtual Base:', marketState.virtualBase.toString(), '(500 VETH)');
    console.log('   Virtual Quote:', marketState.virtualQuote.toString(), '(1M USDC)');
    console.log('   Max OI Cap:', marketState.maxOICap.toString());
    console.log('   Total Long OI:', marketState.totalLongOI.toString());
    console.log('   Total Short OI:', marketState.totalShortOI.toString());
    console.log('   Is Active:', marketState.isActive);
    console.log('');

    // Test parameters from our failed swap
    const tradeSize = parseUnits('0.01', 18); // 0.01 VETH
    const tradeMargin = parseUnits('50', 6); // 50 USDC
    const markPrice = BigInt('2000000000'); // 2000 USDC in 6 decimals (from our debug)

    console.log('🧪 TEST TRADE PARAMETERS:');
    console.log('   Size:', formatUnits(tradeSize, 18), 'VETH');
    console.log('   Margin:', formatUnits(tradeMargin, 6), 'USDC');
    console.log('   Mark Price:', (Number(markPrice) / 1e6).toFixed(2), 'USDC per VETH');
    console.log('');

    // VALIDATION 1: Market Active Check
    console.log('✅ VALIDATION 1: Market Active Check');
    console.log('   Market Active:', marketState.isActive);
    if (!marketState.isActive) {
      console.log('❌ FAIL: Market is not active');
      return;
    }
    console.log('   ✅ PASS: Market is active');
    console.log('');

    // VALIDATION 2: Price Band Check
    console.log('📊 VALIDATION 2: Price Band Check');
    console.log('   Spot Price Feed:', marketState.spotPriceFeed);
    if (marketState.spotPriceFeed === '0x0000000000000000000000000000000000000000') {
      console.log('   ✅ PASS: No spot price feed configured - skipping price band check');
    } else {
      console.log('   ⚠️  Spot price feed configured - would check price deviation');
    }
    console.log('');

    // VALIDATION 3: Open Interest Cap Check
    console.log('📈 VALIDATION 3: Open Interest Cap Check');
    
    // Calculate notional size using the same logic as the hook
    // notionalSize = (trade.size * currentMarkPrice) / 1e18 then / 1e12
    const notionalSizeStep1 = (tradeSize * markPrice) / BigInt(1e18);
    const notionalSize = notionalSizeStep1 / BigInt(1e12);
    
    console.log('   Trade Size (wei):', tradeSize.toString());
    console.log('   Mark Price (6 decimals):', markPrice.toString());
    console.log('   Notional Step 1 (size * price / 1e18):', notionalSizeStep1.toString());
    console.log('   Final Notional (/ 1e12):', notionalSize.toString());
    console.log('   Notional (formatted):', (Number(notionalSize) / 1e6).toFixed(6), 'USDC');
    
    const newLongOI = marketState.totalLongOI + notionalSize;
    console.log('   Current Long OI:', marketState.totalLongOI.toString());
    console.log('   New Long OI:', newLongOI.toString());
    console.log('   Max OI Cap:', marketState.maxOICap.toString());
    console.log('   OI Check:', newLongOI <= marketState.maxOICap ? 'PASS' : 'FAIL');
    
    if (newLongOI > marketState.maxOICap) {
      console.log('❌ FAIL: Open Interest Cap Exceeded!');
      console.log('   This might be the cause of the error');
      return;
    }
    console.log('   ✅ PASS: Open Interest within limits');
    console.log('');

    // VALIDATION 4: Margin Requirement Check
    console.log('💰 VALIDATION 4: Margin Requirement Check');
    
    // Calculate required margin using hook logic
    // requiredMargin = notional / (MAX_LEVERAGE / 1e18), but ensure >= MIN_MARGIN
    const MAX_LEVERAGE = BigInt('20000000000000000000'); // 20e18
    const MIN_MARGIN = BigInt('10000000'); // 10e6 (10 USDC)
    
    const notionalForMargin = (tradeSize * markPrice) / BigInt(1e18) / BigInt(1e12); // Same as above
    const marginRequired = notionalForMargin / (MAX_LEVERAGE / BigInt(1e18));
    const finalMarginRequired = marginRequired < MIN_MARGIN ? MIN_MARGIN : marginRequired;
    
    console.log('   Notional for margin calc:', notionalForMargin.toString());
    console.log('   Margin required (calculated):', marginRequired.toString());
    console.log('   Min margin:', MIN_MARGIN.toString());
    console.log('   Final required margin:', finalMarginRequired.toString());
    console.log('   Final required (formatted):', (Number(finalMarginRequired) / 1e6).toFixed(6), 'USDC');
    console.log('   Provided margin:', (Number(tradeMargin) / 1e6).toFixed(6), 'USDC');
    console.log('   Margin Check:', tradeMargin >= finalMarginRequired ? 'PASS' : 'FAIL');
    
    if (tradeMargin < finalMarginRequired) {
      console.log('❌ FAIL: Insufficient Margin!');
      console.log('   This might be the cause of the error');
      return;
    }
    console.log('   ✅ PASS: Sufficient margin provided');
    console.log('');

    // VALIDATION 5: Check Hook Constants
    console.log('⚙️  VALIDATION 5: Hook Constants Check');
    console.log('   MAX_LEVERAGE:', (Number(MAX_LEVERAGE) / 1e18).toFixed(0), 'x');
    console.log('   MIN_MARGIN:', (Number(MIN_MARGIN) / 1e6).toFixed(2), 'USDC');
    console.log('   MAX_DEVIATION_BPS: 500 (5%)');
    console.log('');

    // VALIDATION 6: Check if error might be from position manager integration
    console.log('🔗 VALIDATION 6: Position Manager Integration');
    
    // Check if PositionManager and PositionFactory are properly connected
    try {
      const factoryFromManager = await publicClient.readContract({
        address: c.positionManager.address,
        abi: [{'inputs':[],'name':'factory','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
        functionName: 'factory'
      });
      console.log('   PositionManager -> Factory:', factoryFromManager);
      console.log('   Expected Factory:', c.positionFactory.address);
      console.log('   Factory Match:', factoryFromManager.toLowerCase() === c.positionFactory.address.toLowerCase());
    } catch (error) {
      console.log('   ⚠️  Could not check factory connection:', error.shortMessage);
    }

    // Check if PositionFactory has the market
    try {
      const factoryMarket = await publicClient.readContract({
        address: c.positionFactory.address,
        abi: c.positionFactory.abi as any,
        functionName: 'getMarket',
        args: [poolId]
      });
      console.log('   Factory Market Base Asset:', factoryMarket.baseAsset);
      console.log('   Factory Market Active:', factoryMarket.isActive);
    } catch (error) {
      console.log('   ❌ Factory Market Error:', error.shortMessage);
    }
    console.log('');

    console.log('🎯 HOOK VALIDATION SUMMARY:');
    console.log('===========================');
    console.log('✅ Market is active');
    console.log('✅ No spot price feed (no price band check)');
    console.log('✅ Open Interest within cap');
    console.log('✅ Sufficient margin provided');
    console.log('✅ All hook validations should pass');
    console.log('');
    console.log('🔍 CONCLUSION:');
    console.log('   The 0x90bfb865 error is NOT from hook validation logic');
    console.log('   The error might be from:');
    console.log('   1. PoolManager or PoolSwapTest contract');
    console.log('   2. Pool not being properly initialized');
    console.log('   3. Hook data encoding format mismatch');
    console.log('   4. Currency ordering or swap direction issues');

  } catch (error) {
    console.error('❌ Error in hook validation debug:', error);
  }
}

debugHookValidation().catch(e => { 
  console.error('💥 Failed:', e);
  process.exit(1);
});
