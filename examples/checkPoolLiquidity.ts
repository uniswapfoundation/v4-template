import 'dotenv/config';
import { createPublicClient, http, defineChain } from 'viem';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';
import { calculateUsdcVethPoolId, getPoolInfo } from './poolUtils';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);

async function checkPoolLiquidity() {
  console.log('🏊 Checking Pool Liquidity and State');
  console.log('===================================');
  
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

  // Calculate pool ID
  const poolId = calculateUsdcVethPoolId(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);
  const poolInfo = getPoolInfo(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);

  console.log('📊 Pool Information:');
  console.log('  Pool ID:', poolId);
  console.log('  Currency0 (lower):', poolInfo.poolKey.currency0);
  console.log('  Currency1 (higher):', poolInfo.poolKey.currency1);
  console.log('  Fee:', poolInfo.poolKey.fee);
  console.log('  Hook:', poolInfo.poolKey.hooks);
  console.log('');

  try {
    // Check pool slot0 (basic pool state)
    console.log('🔍 Checking pool slot0...');
    try {
      const slot0 = await publicClient.readContract({
        address: c.poolManager.address,
        abi: c.poolManager.abi as any,
        functionName: 'getSlot0',
        args: [poolId]
      });
      console.log('✅ Pool slot0:', slot0);
    } catch (error) {
      console.log('❌ Error getting slot0:', error.shortMessage || error.message);
    }

    // Check pool liquidity
    console.log('\n💧 Checking pool liquidity...');
    try {
      const liquidity = await publicClient.readContract({
        address: c.poolManager.address,
        abi: c.poolManager.abi as any,
        functionName: 'getLiquidity',
        args: [poolId]
      });
      console.log('💧 Pool Liquidity:', liquidity.toString());
      
      if (liquidity === 0n) {
        console.log('⚠️  Pool has ZERO liquidity - this might cause swap failures');
        console.log('   Consider adding liquidity before attempting swaps');
      } else {
        console.log('✅ Pool has liquidity available');
      }
    } catch (error) {
      console.log('❌ Error getting liquidity:', error.shortMessage || error.message);
    }

    // Check if pool is initialized
    console.log('\n🔧 Checking if pool is initialized...');
    try {
      const isInitialized = await publicClient.readContract({
        address: c.poolManager.address,
        abi: c.poolManager.abi as any,
        functionName: 'isInitialized',
        args: [poolId]
      });
      console.log('🔧 Pool Initialized:', isInitialized);
    } catch (error) {
      console.log('❌ Error checking initialization:', error.shortMessage || error.message);
    }

    // Check hook state
    console.log('\n🪝 Checking hook state...');
    try {
      const marketState = await publicClient.readContract({
        address: c.perpsHook.address,
        abi: c.perpsHook.abi as any,
        functionName: 'getMarketState',
        args: [poolId]
      });
      console.log('🪝 Hook Market State:', marketState);
    } catch (error) {
      console.log('❌ Error getting hook state:', error.shortMessage || error.message);
    }

    // Check pool manager address
    console.log('\n📋 Contract Addresses:');
    console.log('  PoolManager:', c.poolManager.address);
    console.log('  PoolSwapTest:', c.poolSwapTest.address);
    console.log('  PerpsHook:', c.perpsHook.address);

    console.log('\n💡 Recommendations:');
    console.log('  1. If liquidity is zero, add liquidity to the pool first');
    console.log('  2. Ensure the hook is properly configured for the pool');
    console.log('  3. Check that all contracts are deployed and accessible');
    console.log('  4. Verify the error signature 0x90bfb865 in the hook or pool contracts');

  } catch (error) {
    console.error('❌ Error checking pool:', error);
  }
}

checkPoolLiquidity().catch(e => { 
  console.error('💥 Failed:', e);
  process.exit(1);
});
