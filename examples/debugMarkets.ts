#!/usr/bin/env bun
import { parseUnits, formatUnits, createWalletClient, http, createPublicClient, encodeAbiParameters, keccak256 } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { unichainSepolia } from 'viem/chains';
import { getContracts } from './contracts';

// Constants
const CHAIN_ID = 1301; // Unichain Sepolia
const RPC_URL = 'https://sepolia.unichain.org';

// Get contracts
const c = getContracts();

// Environment setup - handle private key format
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

const account = privateKeyToAccount(PK as `0x${string}`);

// Clients
const publicClient = createPublicClient({
  chain: unichainSepolia,
  transport: http(RPC_URL)
});

const walletClient = createWalletClient({
  account,
  chain: unichainSepolia,
  transport: http(RPC_URL)
});

async function main() {
  try {
    console.log('🔬 Comprehensive Market Debugging');
    console.log('👤 Using account:', account.address);
    
    // Pool configuration
    const poolKey = {
      currency0: c.mockUSDC.address,
      currency1: c.mockVETH.address,
      fee: 3000,
      tickSpacing: 60,
      hooks: c.perpsHook.address
    };
    
    console.log('\n📋 Pool Configuration:');
    console.log('  Currency0 (USDC):', poolKey.currency0);
    console.log('  Currency1 (VETH):', poolKey.currency1);
    console.log('  Fee:', poolKey.fee);
    console.log('  Hooks:', poolKey.hooks);
    
    // Check if pool is initialized
    console.log('\n🔍 Checking Pool Status...');
    try {
      const poolId = keccak256(encodeAbiParameters(
        [
          { name: 'currency0', type: 'address' },
          { name: 'currency1', type: 'address' },
          { name: 'fee', type: 'uint24' },
          { name: 'tickSpacing', type: 'int24' },
          { name: 'hooks', type: 'address' }
        ],
        [poolKey.currency0, poolKey.currency1, poolKey.fee, poolKey.tickSpacing, poolKey.hooks]
      ));
      
      console.log('🆔 Calculated Pool ID:', poolId);
      
      // Check pool manager
      const poolSlot0 = await publicClient.readContract({
        address: c.poolManager.address,
        abi: c.poolManager.abi as any,
        functionName: 'getSlot0',
        args: [poolId]
      }) as any;
      
      console.log('✅ Pool Slot0:', {
        sqrtPriceX96: poolSlot0.sqrtPriceX96?.toString(),
        tick: poolSlot0.tick?.toString(),
        protocolFee: poolSlot0.protocolFee?.toString(),
        lpFee: poolSlot0.lpFee?.toString()
      });
      
      // Check PerpsHook market state
      try {
        const marketState = await publicClient.readContract({
          address: c.perpsHook.address,
          abi: c.perpsHook.abi as any,
          functionName: 'getMarketState',
          args: [poolId]
        }) as any;
        
        console.log('✅ PerpsHook Market State:', {
          virtualBase: marketState.virtualBase?.toString(),
          virtualQuote: marketState.virtualQuote?.toString(),
          isActive: marketState.isActive,
          totalLongOI: marketState.totalLongOI?.toString(),
          totalShortOI: marketState.totalShortOI?.toString()
        });
        
        // Try to get mark price
        const markPrice = await publicClient.readContract({
          address: c.perpsHook.address,
          abi: c.perpsHook.abi as any,
          functionName: 'getMarkPrice',
          args: [poolId]
        }) as bigint;
        
        console.log('💰 Mark Price:', formatUnits(markPrice, 18), 'USDC per VETH');
        
      } catch (error) {
        console.log('❌ PerpsHook market not found for this pool');
      }
      
    } catch (error) {
      console.log('❌ Pool not found or not initialized');
      console.log('Error:', error);
    }
    
    // Check user balances and setup
    console.log('\n💰 User Balance Check:');
    const usdcBalance = await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    }) as bigint;
    
    const vethBalance = await publicClient.readContract({
      address: c.mockVETH.address,
      abi: c.mockVETH.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    }) as bigint;
    
    const marginBalance = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'getTotalBalance',
      args: [account.address]
    }) as bigint;
    
    console.log('  USDC Balance:', formatUnits(usdcBalance, 6));
    console.log('  VETH Balance:', formatUnits(vethBalance, 18));
    console.log('  Margin Account:', formatUnits(marginBalance, 6), 'USDC');
    
    // Check allowances
    console.log('\n🔐 Allowance Check:');
    const usdcAllowanceForSwapTest = await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'allowance',
      args: [account.address, c.poolSwapTest.address]
    }) as bigint;
    
    const vethAllowanceForSwapTest = await publicClient.readContract({
      address: c.mockVETH.address,
      abi: c.mockVETH.abi as any,
      functionName: 'allowance',
      args: [account.address, c.poolSwapTest.address]
    }) as bigint;
    
    console.log('  USDC → PoolSwapTest:', formatUnits(usdcAllowanceForSwapTest, 6));
    console.log('  VETH → PoolSwapTest:', formatUnits(vethAllowanceForSwapTest, 18));
    
    // Test a minimal trade params encoding
    console.log('\n🧪 Testing TradeParams Encoding:');
    const tradeParams = {
      operation: 0,              // OPEN_LONG
      tokenId: BigInt(0),        // New position
      size: parseUnits('0.01', 18),   // Very small size: 0.01 VETH
      margin: parseUnits('50', 6),    // Small margin: 50 USDC
      maxSlippage: BigInt(1000),      // 10% slippage
      trader: account.address
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
    
    console.log('✅ TradeParams encoded successfully');
    console.log('  Operation:', tradeParams.operation, '(OPEN_LONG)');
    console.log('  Size:', formatUnits(tradeParams.size, 18), 'VETH');
    console.log('  Margin:', formatUnits(tradeParams.margin, 6), 'USDC');
    console.log('  Hook Data Length:', hookData.length);
    
    console.log('\n✨ Summary:');
    console.log('  🔶 Pool ID calculated');
    console.log('  🔶 User has balances');
    console.log('  🔶 TradeParams encoding works');
    console.log('  🔶 Ready for testing small position');

  } catch (error) {
    console.error('❌ Error in debugging:', error);
    throw error;
  }
}

if (import.meta.main) {
  main().catch(console.error);
}
