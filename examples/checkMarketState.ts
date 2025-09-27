#!/usr/bin/env bun
import { createPublicClient, http } from 'viem';
import { unichainSepolia } from 'viem/chains';
import { getContracts } from './contracts';

// Constants
const RPC_URL = 'https://sepolia.unichain.org';

// Get contracts
const c = getContracts();

// Client
const publicClient = createPublicClient({
  chain: unichainSepolia,
  transport: http(RPC_URL)
});

// Calculate pool ID using the same logic as in our swap script
function calculatePoolId() {
  // Create poolKey first
  const poolKey = {
    currency0: c.mockUSDC.address,
    currency1: c.mockVETH.address,
    fee: 3000,
    tickSpacing: 60,
    hooks: c.perpsHook.address
  };
  
  console.log('Pool Key:');
  console.log('  Currency0:', poolKey.currency0);
  console.log('  Currency1:', poolKey.currency1);
  console.log('  Fee:', poolKey.fee);
  console.log('  TickSpacing:', poolKey.tickSpacing);
  console.log('  Hooks:', poolKey.hooks);
  
  // For now, let's use a known pool ID from our previous logs
  // From the swap logs, we can see the poolId in the hookData
  return '0x84c7c2e3facd5b2fd2a0d94b09c77a49b0b9d6f8b60b7b3f3c3a7f9e3c1b5d6b';
}

async function main() {
  try {
    console.log('🔍 Checking PerpsHook Market State');
    
    const poolIdHex = calculatePoolId();
    console.log('🆔 Calculated Pool ID:', poolIdHex);
    
    // Try to get market state from PerpsHook
    try {
      const marketState = await publicClient.readContract({
        address: c.perpsHook.address,
        abi: c.perpsHook.abi as any,
        functionName: 'getMarketState',
        args: [`0x${poolIdHex}`]
      }) as any;
      
      console.log('✅ Market State Found:');
      console.log('  Virtual Base:', marketState.virtualBase?.toString());
      console.log('  Virtual Quote:', marketState.virtualQuote?.toString());
      console.log('  K Constant:', marketState.k?.toString());
      console.log('  Is Active:', marketState.isActive);
      console.log('  Total Long OI:', marketState.totalLongOI?.toString());
      console.log('  Total Short OI:', marketState.totalShortOI?.toString());
      console.log('  Max OI Cap:', marketState.maxOICap?.toString());
      
    } catch (error) {
      console.log('❌ Failed to get market state:', error);
    }
    
    // Try to get mark price
    try {
      const markPrice = await publicClient.readContract({
        address: c.perpsHook.address,
        abi: c.perpsHook.abi as any,
        functionName: 'getMarkPrice',
        args: [`0x${poolIdHex}`]
      }) as bigint;
      
      console.log('💰 Mark Price:', markPrice.toString(), 'wei (', Number(markPrice) / 1e18, 'ETH/USD)');
      
    } catch (error) {
      console.log('❌ Failed to get mark price:', error);
    }
    
  } catch (error) {
    console.error('❌ Error checking market state:', error);
    throw error;
  }
}

if (import.meta.main) {
  main().catch(console.error);
}
