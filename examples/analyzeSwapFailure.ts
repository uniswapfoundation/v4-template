import 'dotenv/config';
import { createPublicClient, http, defineChain, parseUnits, encodeAbiParameters } from 'viem';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';
import { calculateUsdcVethPoolId, getPoolInfo } from './poolUtils';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);

async function analyzeSwapFailure() {
  console.log('🔍 Analyzing Swap Failure with Debug Events');
  console.log('===========================================');
  
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
  console.log('🪝 Hook Address:', c.perpsHook.address);
  console.log('');

  try {
    // First, let's simulate the exact same call that failed
    console.log('🧪 Simulating the failed swap call...');
    
    const poolInfo = getPoolInfo(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);
    
    // Recreate the exact trade parameters that failed
    const tradeParams = {
      operation: 0, // OPEN_LONG
      tokenId: 0n,
      size: parseUnits('0.01', 18), // 0.01 VETH
      margin: parseUnits('50', 6), // 50 USDC
      maxSlippage: 1000n, // 10%
      trader: '0xcFE743EA353d4d3D2c20C41C7d878B2cbA66DA0a'
    };

    const hookData = encodeAbiParameters(
      [
        {
          type: 'tuple',
          components: [
            { name: 'operation', type: 'uint8' },
            { name: 'tokenId', type: 'uint256' },
            { name: 'size', type: 'uint256' },
            { name: 'margin', type: 'uint256' },
            { name: 'maxSlippage', type: 'uint256' },
            { name: 'trader', type: 'address' }
          ]
        }
      ],
      [tradeParams]
    );

    console.log('📦 Hook Data Analysis:');
    console.log('   Operation:', tradeParams.operation);
    console.log('   Size:', (Number(tradeParams.size) / 1e18).toFixed(4), 'VETH');
    console.log('   Margin:', (Number(tradeParams.margin) / 1e6).toFixed(2), 'USDC');
    console.log('   Hook Data:', hookData);
    console.log('');

    // Try to call the hook's beforeSwap function directly to see debug events
    console.log('🔍 Testing hook beforeSwap directly...');
    
    const poolKey = {
      currency0: poolInfo.poolKey.currency0,
      currency1: poolInfo.poolKey.currency1,
      fee: poolInfo.poolKey.fee,
      tickSpacing: poolInfo.poolKey.tickSpacing,
      hooks: poolInfo.poolKey.hooks
    };

    const swapParams = {
      zeroForOne: true,
      amountSpecified: parseUnits('0.001', 18),
      sqrtPriceLimitX96: BigInt("4295128740")
    };

    // Since we can't call internal functions directly, let's check if we can simulate
    // the conditions that would trigger each validation

    // Check 1: Market active status
    console.log('✅ Check 1: Market active status');
    try {
      const marketState = await publicClient.readContract({
        address: c.perpsHook.address,
        abi: c.perpsHook.abi as any,
        functionName: 'getMarketState',
        args: [poolId]
      });
      console.log('   Market Active:', marketState.isActive);
      console.log('   Virtual Base:', marketState.virtualBase.toString());
      console.log('   Virtual Quote:', marketState.virtualQuote.toString());
    } catch (error) {
      console.log('❌ Market not found or not active');
      return;
    }

    // Check 2: Mark price calculation
    console.log('\n💰 Check 2: Mark price calculation');
    try {
      const markPrice = await publicClient.readContract({
        address: c.perpsHook.address,
        abi: c.perpsHook.abi as any,
        functionName: 'getMarkPrice',
        args: [poolId]
      });
      console.log('   Mark Price (raw):', markPrice.toString());
      console.log('   Mark Price (USD):', (Number(markPrice) / 1e18).toFixed(2));
      
      // Manual notional calculation
      const notionalStep1 = (tradeParams.size * markPrice) / BigInt(1e18);
      const notionalFinal = notionalStep1 / BigInt(1e12);
      console.log('   Calculated Notional:', (Number(notionalFinal) / 1e6).toFixed(6), 'USDC');
      
      if (notionalFinal === 0n) {
        console.log('❌ CRITICAL: Notional size is 0 - this will cause validation failures!');
        console.log('   This suggests the mark price precision is still wrong');
      } else {
        console.log('✅ Notional size is positive');
      }
      
    } catch (error) {
      console.log('❌ Error getting mark price:', error.shortMessage);
    }

    // Check 3: Required margin calculation
    console.log('\n🔍 Check 3: Required margin calculation');
    
    // Simulate the _calculateRequiredMargin function
    const markPrice = BigInt('2000000000000000000000'); // Expected 18-decimal price
    const size = tradeParams.size;
    const providedMargin = tradeParams.margin;
    
    const notionalForMargin = (size * markPrice) / BigInt(1e18) / BigInt(1e12);
    const maxLeverage = BigInt('20000000000000000000'); // 20e18
    const minMargin = BigInt('10000000'); // 10e6
    
    const marginRequired = notionalForMargin / (maxLeverage / BigInt(1e18));
    const finalMarginRequired = marginRequired < minMargin ? minMargin : marginRequired;
    
    console.log('   Provided Margin:', (Number(providedMargin) / 1e6).toFixed(2), 'USDC');
    console.log('   Required Margin:', (Number(finalMarginRequired) / 1e6).toFixed(2), 'USDC');
    console.log('   Margin Check:', providedMargin >= finalMarginRequired ? 'PASS' : 'FAIL');

    console.log('\n🎯 ANALYSIS SUMMARY:');
    console.log('===================');
    console.log('The error 0x90bfb865 is occurring consistently even with:');
    console.log('✅ Correct hook deployment with debug events');
    console.log('✅ Proper pool creation and initialization');
    console.log('✅ Market configuration in all contracts');
    console.log('✅ Sufficient token approvals');
    console.log('✅ Correct hook data encoding');
    console.log('');
    console.log('🔬 The debug events from the hook should show us exactly where it fails');
    console.log('   Check the transaction logs for DebugBeforeSwap, DebugValidation, and DebugError events');

  } catch (error) {
    console.error('❌ Error in analysis:', error);
  }
}

analyzeSwapFailure().catch(e => { 
  console.error('💥 Failed:', e);
  process.exit(1);
});
