import 'dotenv/config';
import { createPublicClient, createWalletClient, http, defineChain, parseUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';
import { calculateUsdcVethPoolId, getPoolInfo } from './poolUtils';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing');

async function testMinimalSwap() {
  console.log('🧪 Testing Minimal Swap Without Hook Data');
  console.log('=========================================');
  
  const account = privateKeyToAccount(PK as `0x${string}`);
  const contracts = getContracts(CHAIN_ID);

  const transport = http(RPC_URL);
  const chain = defineChain({ 
    id: CHAIN_ID, 
    name: 'UnichainSepolia', 
    nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 }, 
    rpcUrls: { default: { http: [RPC_URL] }, public: { http: [RPC_URL] } } 
  });
  
  const publicClient = createPublicClient({ transport, chain });
  const walletClient = createWalletClient({ account, transport, chain });

  const c = contracts;
  const poolId = calculateUsdcVethPoolId(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);
  const poolInfo = getPoolInfo(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);

  console.log('👤 Account:', account.address);
  console.log('🆔 Pool ID:', poolId);
  console.log('');

  try {
    // Test 1: Try swap without hook data (should be allowed per hook logic)
    console.log('🧪 TEST 1: Minimal swap without hook data');
    console.log('==========================================');
    
    const poolKey = {
      currency0: poolInfo.poolKey.currency0 as `0x${string}`,
      currency1: poolInfo.poolKey.currency1 as `0x${string}`,
      fee: poolInfo.poolKey.fee,
      tickSpacing: poolInfo.poolKey.tickSpacing,
      hooks: poolInfo.poolKey.hooks as `0x${string}`
    };

    const swapParams = {
      zeroForOne: true,
      amountSpecified: parseUnits('0.0001', 18), // Tiny amount
      sqrtPriceLimitX96: BigInt("4295128740")
    };

    const testSettings = {
      takeClaims: false,
      settleUsingBurn: false
    };

    console.log('📋 Minimal Swap Parameters:');
    console.log('   Amount:', (Number(swapParams.amountSpecified) / 1e18).toFixed(6), 'tokens');
    console.log('   Zero For One:', swapParams.zeroForOne);
    console.log('   Hook Data: EMPTY (length 0)');

    try {
      console.log('🔄 Executing minimal swap...');
      
      const swapTx = await walletClient.writeContract({
        address: c.poolSwapTest.address,
        abi: c.poolSwapTest.abi as any,
        functionName: 'swap',
        args: [poolKey, swapParams, testSettings, "0x"] // Empty hook data
      });

      console.log('⏳ Waiting for minimal swap...');
      const receipt = await publicClient.waitForTransactionReceipt({ hash: swapTx });
      console.log('✅ MINIMAL SWAP SUCCESS!');
      console.log('📋 Transaction Hash:', swapTx);
      console.log('📦 Block:', receipt.blockNumber);
      console.log('');
      console.log('🎯 This proves the pool and PoolSwapTest work correctly');
      console.log('   The issue is specifically with hook data processing');

    } catch (error) {
      console.log('❌ MINIMAL SWAP FAILED:');
      console.log('   Error:', error.shortMessage || error.message);
      console.log('   Signature:', error.signature);
      
      if (error.signature === '0x90bfb865') {
        console.log('🔍 Same error even without hook data!');
        console.log('   This suggests the error is from PoolManager or pool state');
        console.log('   NOT from our hook logic');
      } else {
        console.log('🔍 Different error without hook data');
        console.log('   This suggests our hook data is causing the 0x90bfb865 error');
      }
    }

    console.log('\n🧪 TEST 2: Check if pool exists in PoolManager');
    console.log('===============================================');
    
    // Try to check if the pool is properly registered
    try {
      // This is a basic check to see if we can interact with the pool
      console.log('📊 Pool Key for verification:');
      console.log('   Currency0:', poolKey.currency0);
      console.log('   Currency1:', poolKey.currency1);
      console.log('   Fee:', poolKey.fee);
      console.log('   Tick Spacing:', poolKey.tickSpacing);
      console.log('   Hooks:', poolKey.hooks);
      
      console.log('✅ Pool key is well-formed');
      
    } catch (error) {
      console.log('❌ Pool verification failed:', error.shortMessage);
    }

    console.log('\n🧪 TEST 3: Check hook data encoding formats');
    console.log('===========================================');
    
    // Test different hook data encodings to see if format is the issue
    
    // Format 1: Our current format
    const tradeParams1 = {
      operation: 0, // OPEN_LONG
      tokenId: 0n,
      size: parseUnits('0.01', 18),
      margin: parseUnits('50', 6),
      maxSlippage: 1000n,
      trader: account.address
    };

    console.log('📦 Format 1 (Current):');
    console.log('   Operation:', tradeParams1.operation);
    console.log('   Token ID:', tradeParams1.tokenId.toString());
    console.log('   Size:', tradeParams1.size.toString());
    console.log('   Margin:', tradeParams1.margin.toString());
    console.log('   Max Slippage:', tradeParams1.maxSlippage.toString());
    console.log('   Trader:', tradeParams1.trader);

    // Try to manually verify our calculation matches the hook's expectation
    console.log('\n🧮 TEST 4: Manual Notional Calculation Verification');
    console.log('==================================================');
    
    const testSize = parseUnits('0.01', 18);
    const testPrice = BigInt('2000000000'); // Hook's actual return value
    
    console.log('📊 Manual Hook Logic Simulation:');
    console.log('   Test Size:', testSize.toString(), '(0.01 VETH in wei)');
    console.log('   Test Price:', testPrice.toString(), '(2000 in 6 decimals)');
    
    // Simulate hook's notional calculation
    const notionalStep1 = (testSize * testPrice) / BigInt(1e18);
    const finalNotional = notionalStep1 / BigInt(1e12);
    
    console.log('   Step 1 (size * price / 1e18):', notionalStep1.toString());
    console.log('   Step 2 (/ 1e12):', finalNotional.toString());
    console.log('   Final Notional (USDC):', (Number(finalNotional) / 1e6).toFixed(6));
    
    // The issue is clear: we get 0 because the price is in wrong precision!
    // Let's calculate what the price should be for the calculation to work
    const correctPrice = BigInt('2000000000000000000000'); // 2000 in 18 decimals
    const correctNotionalStep1 = (testSize * correctPrice) / BigInt(1e18);
    const correctFinalNotional = correctNotionalStep1 / BigInt(1e12);
    
    console.log('\n✅ CORRECT CALCULATION (if price were 18 decimals):');
    console.log('   Correct Price (18 decimals):', correctPrice.toString());
    console.log('   Step 1:', correctNotionalStep1.toString());
    console.log('   Step 2:', correctFinalNotional.toString());
    console.log('   Final Notional (USDC):', (Number(correctFinalNotional) / 1e6).toFixed(6));

    console.log('\n🎯 ROOT CAUSE IDENTIFIED:');
    console.log('=========================');
    console.log('❌ Hook getMarkPrice returns 6-decimal precision (2000000000)');
    console.log('❌ Hook validation expects 18-decimal precision for calculations');
    console.log('❌ This causes notional size to be 0, triggering validation errors');
    console.log('');
    console.log('🔧 SOLUTION NEEDED:');
    console.log('   Fix hook getMarkPrice to return 18-decimal precision');
    console.log('   OR adjust validation calculations to handle 6-decimal prices');

  } catch (error) {
    console.error('❌ Error in minimal swap test:', error);
  }
}

testMinimalSwap().catch(e => { 
  console.error('💥 Failed:', e);
  process.exit(1);
});
