import 'dotenv/config';
import { createPublicClient, http, defineChain } from 'viem';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';
import { calculateUsdcVethPoolId } from './poolUtils';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);

async function debugPricePrecision() {
  console.log('🔬 DEBUG: Price Precision Analysis');
  console.log('==================================');
  
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
    // Get vAMM state
    const marketState = await publicClient.readContract({
      address: c.perpsHook.address,
      abi: c.perpsHook.abi as any,
      functionName: 'getMarketState',
      args: [poolId]
    });
    
    console.log('📊 RAW vAMM DATA:');
    console.log('   Virtual Base (BigInt):', marketState.virtualBase);
    console.log('   Virtual Quote (BigInt):', marketState.virtualQuote);
    console.log('   K Constant (BigInt):', marketState.k);
    console.log('');

    // Convert to strings to avoid precision loss
    const virtualBaseStr = marketState.virtualBase.toString();
    const virtualQuoteStr = marketState.virtualQuote.toString();
    const kStr = marketState.k.toString();

    console.log('📊 STRING REPRESENTATIONS:');
    console.log('   Virtual Base (string):', virtualBaseStr);
    console.log('   Virtual Quote (string):', virtualQuoteStr);
    console.log('   K Constant (string):', kStr);
    console.log('');

    // Manual price calculations using BigInt arithmetic
    console.log('🧮 BIGINT PRICE CALCULATIONS:');
    
    // Method 1: Using BigInt arithmetic
    const virtualBaseBigInt = marketState.virtualBase;
    const virtualQuoteBigInt = marketState.virtualQuote;
    
    // Price = (virtualQuote * 1e18) / virtualBase
    const priceNumerator = virtualQuoteBigInt * BigInt(1e18);
    const price = priceNumerator / virtualBaseBigInt;
    
    console.log('   Price Numerator:', priceNumerator.toString());
    console.log('   Price (BigInt):', price.toString());
    console.log('   Price (formatted):', (Number(price) / 1e18).toFixed(6), 'USDC per VETH');
    console.log('');

    // Method 2: Expected calculation for 2000 USD price
    console.log('🎯 EXPECTED CALCULATION VERIFICATION:');
    const expectedVirtualBase = BigInt('500000000000000000000'); // 500 VETH in wei
    const expectedVirtualQuote = BigInt('1000000000000'); // 1M USDC in 6 decimals
    const expectedPrice = (expectedVirtualQuote * BigInt(1e18)) / expectedVirtualBase;
    
    console.log('   Expected Virtual Base:', expectedVirtualBase.toString());
    console.log('   Expected Virtual Quote:', expectedVirtualQuote.toString());
    console.log('   Expected Price (BigInt):', expectedPrice.toString());
    console.log('   Expected Price (formatted):', (Number(expectedPrice) / 1e18).toFixed(6), 'USDC per VETH');
    console.log('');

    // Method 3: Check what the hook's getMarkPrice returns
    console.log('📊 HOOK MARK PRICE ANALYSIS:');
    
    try {
      const hookMarkPrice = await publicClient.readContract({
        address: c.perpsHook.address,
        abi: c.perpsHook.abi as any,
        functionName: 'getMarkPrice',
        args: [poolId]
      });
      
      console.log('   Hook Mark Price (BigInt):', hookMarkPrice);
      console.log('   Hook Mark Price (string):', hookMarkPrice.toString());
      console.log('   Hook Mark Price (formatted 18 decimals):', (Number(hookMarkPrice) / 1e18).toFixed(6));
      console.log('   Hook Mark Price (formatted 9 decimals):', (Number(hookMarkPrice) / 1e9).toFixed(6));
      console.log('   Hook Mark Price (formatted 6 decimals):', (Number(hookMarkPrice) / 1e6).toFixed(6));
      
    } catch (error) {
      console.log('❌ Hook Mark Price Error:', error.shortMessage);
    }

    // Method 4: Check FundingOracle mark price
    console.log('📊 FUNDING ORACLE MARK PRICE ANALYSIS:');
    
    try {
      const fundingMarkPrice = await publicClient.readContract({
        address: c.fundingOracle.address,
        abi: c.fundingOracle.abi as any,
        functionName: 'getMarkPrice',
        args: [poolId]
      });
      
      console.log('   Funding Oracle Mark Price (BigInt):', fundingMarkPrice);
      console.log('   Funding Oracle Mark Price (string):', fundingMarkPrice.toString());
      console.log('   Funding Oracle Mark Price (formatted 18 decimals):', (Number(fundingMarkPrice) / 1e18).toFixed(6));
      console.log('   Funding Oracle Mark Price (formatted 9 decimals):', (Number(fundingMarkPrice) / 1e9).toFixed(6));
      console.log('   Funding Oracle Mark Price (formatted 6 decimals):', (Number(fundingMarkPrice) / 1e6).toFixed(6));
      
    } catch (error) {
      console.log('❌ Funding Oracle Mark Price Error:', error.shortMessage);
    }
    console.log('');

    // Method 5: Check if the issue is with virtual reserve precision
    console.log('🔍 VIRTUAL RESERVE PRECISION ANALYSIS:');
    console.log('=====================================');
    
    console.log('Virtual Base Analysis:');
    console.log('   Raw value:', virtualBaseBigInt.toString());
    console.log('   In ETH (18 decimals):', (Number(virtualBaseBigInt) / 1e18).toFixed(6), 'VETH');
    console.log('   Expected: 500 VETH');
    
    console.log('Virtual Quote Analysis:');
    console.log('   Raw value:', virtualQuoteBigInt.toString());
    console.log('   In USDC (6 decimals):', (Number(virtualQuoteBigInt) / 1e6).toFixed(6), 'USDC');
    console.log('   Expected: 1,000,000 USDC');
    
    // Check if the virtual reserves match our rebalancing
    const isVirtualBaseCorrect = virtualBaseBigInt === BigInt('500000000000000000000');
    const isVirtualQuoteCorrect = virtualQuoteBigInt === BigInt('1000000000000');
    
    console.log('✅ Virtual Base Correct:', isVirtualBaseCorrect);
    console.log('✅ Virtual Quote Correct:', isVirtualQuoteCorrect);
    
    if (isVirtualBaseCorrect && isVirtualQuoteCorrect) {
      console.log('🎯 vAMM reserves are exactly as expected!');
      console.log('   The price calculation issue must be elsewhere');
    }

    console.log('\n🔬 CONCLUSION:');
    console.log('==============');
    if (isVirtualBaseCorrect && isVirtualQuoteCorrect) {
      console.log('✅ vAMM virtual reserves are perfectly balanced');
      console.log('❌ The 0x90bfb865 error is NOT related to vAMM balance');
      console.log('🔍 The error is likely in:');
      console.log('   1. Hook beforeSwap validation logic');
      console.log('   2. Pool initialization state');
      console.log('   3. PoolSwapTest compatibility');
      console.log('   4. Hook data interpretation');
    } else {
      console.log('❌ vAMM virtual reserves are incorrect');
      console.log('🔧 Need to fix the emergency rebalance function');
    }

  } catch (error) {
    console.error('❌ Error in price precision debug:', error);
  }
}

debugPricePrecision().catch(e => { 
  console.error('💥 Failed:', e);
  process.exit(1);
});
