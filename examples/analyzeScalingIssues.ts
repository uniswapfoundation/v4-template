import 'dotenv/config';
import { createPublicClient, http, defineChain, parseUnits, formatUnits } from 'viem';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';
import { calculateUsdcVethPoolId } from './poolUtils';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);

async function analyzeScalingIssues() {
  console.log('🔬 ANALYZING SCALING ISSUES ACROSS ALL CONTRACTS');
  console.log('================================================');
  
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
    // ANALYSIS 1: Hook vAMM State and Price Calculation
    console.log('📊 ANALYSIS 1: Hook vAMM State and Price Calculation');
    console.log('===================================================');
    
    const marketState = await publicClient.readContract({
      address: c.perpsHook.address,
      abi: c.perpsHook.abi as any,
      functionName: 'getMarketState',
      args: [poolId]
    });
    
    console.log('🪝 Current vAMM State:');
    console.log('   Virtual Base (raw):', marketState.virtualBase.toString());
    console.log('   Virtual Quote (raw):', marketState.virtualQuote.toString());
    console.log('   K Constant:', marketState.k.toString());
    
    const virtualBase = Number(marketState.virtualBase);
    const virtualQuote = Number(marketState.virtualQuote);
    
    console.log('📊 Converted Values:');
    console.log('   Virtual Base (VETH):', (virtualBase / 1e18).toFixed(6));
    console.log('   Virtual Quote (USDC):', (virtualQuote / 1e6).toFixed(2));
    
    // Manual price calculation
    const manualPrice = (virtualQuote * 1e30) / virtualBase;
    console.log('   Manual Price Calc:', (Number(manualPrice) / 1e18).toFixed(2), 'USD');
    
    // Check hook's mark price
    const hookMarkPrice = await publicClient.readContract({
      address: c.perpsHook.address,
      abi: c.perpsHook.abi as any,
      functionName: 'getMarkPrice',
      args: [poolId]
    });
    console.log('   Hook Mark Price:', (Number(hookMarkPrice) / 1e18).toFixed(2), 'USD');
    
    // PROBLEM ANALYSIS: Check if virtual reserves are reasonable
    if (virtualBase < 1e15) { // Less than 0.001 VETH
      console.log('❌ PROBLEM: Virtual Base is too small!');
      console.log('   Current:', virtualBase, 'wei');
      console.log('   Should be around:', '500000000000000000000', 'wei (500 VETH)');
    }
    
    if (virtualQuote > 1e15) { // More than 1B USDC
      console.log('❌ PROBLEM: Virtual Quote is too large!');
      console.log('   Current:', virtualQuote, '(6 decimals)');
      console.log('   Should be around:', '1000000000000', '(1M USDC in 6 decimals)');
    }
    console.log('');

    // ANALYSIS 2: Position Size and Margin Calculations
    console.log('📈 ANALYSIS 2: Position Size and Margin Calculations');
    console.log('===================================================');
    
    const testMargin = parseUnits('100', 6); // 100 USDC
    const testLeverage = 2; // 2x leverage
    const markPrice = Number(hookMarkPrice);
    
    console.log('🧮 Test Position Calculation:');
    console.log('   Margin:', formatUnits(testMargin, 6), 'USDC');
    console.log('   Leverage:', testLeverage, 'x');
    console.log('   Mark Price:', (markPrice / 1e18).toFixed(2), 'USD');
    
    // Calculate position size (this is where the problem likely is)
    const notionalValue = Number(testMargin) * testLeverage; // In USDC (6 decimals)
    const positionSizeInUSD = notionalValue / 1e6; // Convert to actual USD
    const positionSizeInVETH = positionSizeInUSD / (markPrice / 1e18); // VETH amount
    const positionSizeWei = BigInt(Math.floor(positionSizeInVETH * 1e18)); // Convert to wei
    
    console.log('   Notional Value:', notionalValue, '(6 decimals) =', (notionalValue / 1e6).toFixed(2), 'USD');
    console.log('   Position Size USD:', positionSizeInUSD.toFixed(2), 'USD');
    console.log('   Position Size VETH:', positionSizeInVETH.toFixed(6), 'VETH');
    console.log('   Position Size Wei:', positionSizeWei.toString());
    
    if (positionSizeWei > BigInt('1000000000000000000000')) { // More than 1000 VETH
      console.log('❌ PROBLEM: Position size is too large!');
      console.log('   This could cause overflow or allowance issues');
    } else {
      console.log('✅ Position size is reasonable');
    }
    console.log('');

    // ANALYSIS 3: Token Allowance Requirements
    console.log('💰 ANALYSIS 3: Token Allowance Analysis');
    console.log('======================================');
    
    // Check what allowances would be needed for the position
    const marginInWei = testMargin;
    const positionValueInUSDC = (positionSizeInVETH * (markPrice / 1e18)) * 1e6; // USDC in 6 decimals
    
    console.log('🔍 Required Allowances:');
    console.log('   Margin (USDC):', formatUnits(marginInWei, 6), 'USDC');
    console.log('   Position Value (USDC):', (positionValueInUSDC / 1e6).toFixed(2), 'USDC');
    console.log('   Position Size (VETH):', positionSizeInVETH.toFixed(6), 'VETH');
    
    // The issue might be that we need allowances for the full position value, not just margin
    const requiredUSDCAllowance = Math.max(Number(marginInWei), positionValueInUSDC);
    const requiredVETHAllowance = positionSizeInVETH * 1e18;
    
    console.log('🎯 Estimated Required Allowances:');
    console.log('   USDC Allowance:', (requiredUSDCAllowance / 1e6).toFixed(2), 'USDC');
    console.log('   VETH Allowance:', (requiredVETHAllowance / 1e18).toFixed(6), 'VETH');
    console.log('');

    // ANALYSIS 4: Recommended Scaling Fixes
    console.log('🔧 ANALYSIS 4: Recommended Scaling Fixes');
    console.log('=======================================');
    
    console.log('💡 SCALING RECOMMENDATIONS:');
    console.log('');
    
    console.log('1. 📉 REDUCE VIRTUAL RESERVES:');
    console.log('   Current Virtual Base: 500000000 (500M wei - too small)');
    console.log('   Recommended Virtual Base: 50000000000000000000 (50 VETH)');
    console.log('   Current Virtual Quote: 1000000000000 (1M USDC)');
    console.log('   Recommended Virtual Quote: 100000000000 (100K USDC)');
    console.log('   This would give same 2000 USD price with smaller numbers');
    console.log('');
    
    console.log('2. 🔢 ADJUST POSITION SIZE CALCULATIONS:');
    console.log('   Use smaller test positions (0.001 VETH instead of 0.1 VETH)');
    console.log('   Use smaller margins (10-20 USDC instead of 100+ USDC)');
    console.log('   This reduces the risk of overflow in calculations');
    console.log('');
    
    console.log('3. 💳 INCREASE TOKEN ALLOWANCES:');
    console.log('   Current approvals might be too small for position operations');
    console.log('   Approve larger amounts (10K USDC, 100 VETH) for safety');
    console.log('   This prevents ERC20InsufficientAllowance errors');
    console.log('');
    
    console.log('4. 🎯 RECOMMENDED EMERGENCY REBALANCE:');
    const recommendedVirtualBase = parseUnits('50', 18); // 50 VETH
    const recommendedVirtualQuote = parseUnits('100000', 6); // 100K USDC
    const expectedPrice = (Number(recommendedVirtualQuote) * 1e30) / Number(recommendedVirtualBase);
    
    console.log('   New Virtual Base:', recommendedVirtualBase.toString(), '(50 VETH)');
    console.log('   New Virtual Quote:', recommendedVirtualQuote.toString(), '(100K USDC)');
    console.log('   Expected Price:', (expectedPrice / 1e18).toFixed(2), 'USD');
    console.log('');
    
    console.log('🚀 NEXT STEPS:');
    console.log('1. Use emergencyRebalanceVAMM with smaller, more reasonable values');
    console.log('2. Increase token allowances in all scripts');
    console.log('3. Test with smaller position sizes initially');
    console.log('4. The swap operations should then work correctly!');

  } catch (error) {
    console.error('❌ Error in scaling analysis:', error);
  }
}

analyzeScalingIssues().catch(e => { 
  console.error('💥 Failed:', e);
  process.exit(1);
});
