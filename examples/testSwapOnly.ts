#!/usr/bin/env bun
import { parseUnits, formatUnits, createWalletClient, http, createPublicClient, encodeAbiParameters } from 'viem';
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
    console.log('🧪 Testing Swap Without Position Creation');
    console.log('👤 Using account:', account.address);
    
    // Pool configuration
    const poolKey = {
      currency0: c.mockUSDC.address,
      currency1: c.mockVETH.address,
      fee: 3000,
      tickSpacing: 60,
      hooks: c.perpsHook.address
    };

    console.log('\n💱 Pool Configuration:');
    console.log('  Currency0 (USDC):', poolKey.currency0);
    console.log('  Currency1 (VETH):', poolKey.currency1);
    console.log('  Fee:', poolKey.fee);
    console.log('  Hook:', poolKey.hooks);

    // Very minimal swap - just to test the hook without position creation
    const swapAmount = parseUnits('0.001', 18); // 0.001 tokens - very minimal
    const sqrtPriceLimitX96 = "4295128740"; // Proper price limit

    const swapParams = {
      zeroForOne: true, // Swap token0 for token1
      amountSpecified: swapAmount,
      sqrtPriceLimitX96: BigInt(sqrtPriceLimitX96)
    };

    const testSettings = {
      takeClaims: false,
      settleUsingBurn: false
    };

    console.log('\n🔧 Swap Parameters:');
    console.log('  Amount:', formatUnits(swapAmount, 18), 'tokens');
    console.log('  Zero for One:', swapParams.zeroForOne);
    console.log('  Price Limit:', sqrtPriceLimitX96);

    // Create hookData for testing different operations
    const testCases = [
      // Test 1: Empty hookData (no position operations)
      {
        name: 'Empty Hook Data',
        hookData: '0x'
      },
      // Test 2: Invalid operation (should trigger hook but not position logic)
      {
        name: 'Invalid Operation', 
        hookData: encodeAbiParameters(
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
          [{
            operation: 99,              // Invalid operation (not 0-5)
            tokenId: BigInt(0),
            size: parseUnits('0.001', 18),
            margin: parseUnits('10', 6),
            maxSlippage: BigInt(1000),
            trader: account.address
          }]
        )
      }
    ];

    // Check allowances first
    const usdcAllowance = await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'allowance',
      args: [account.address, c.poolSwapTest.address]
    }) as bigint;

    const vethAllowance = await publicClient.readContract({
      address: c.mockVETH.address,
      abi: c.mockVETH.abi as any,
      functionName: 'allowance',
      args: [account.address, c.poolSwapTest.address]
    }) as bigint;

    console.log('\n🔐 Current Allowances:');
    console.log('  USDC → PoolSwapTest:', formatUnits(usdcAllowance, 6));
    console.log('  VETH → PoolSwapTest:', formatUnits(vethAllowance, 18));

    if (usdcAllowance < swapAmount || vethAllowance < swapAmount) {
      console.log('🔓 Approving tokens for PoolSwapTest...');
      
      if (usdcAllowance < swapAmount) {
        const approveUSDCTx = await walletClient.writeContract({
          address: c.mockUSDC.address,
          abi: c.mockUSDC.abi as any,
          functionName: 'approve',
          args: [c.poolSwapTest.address, parseUnits('1000', 6)]
        });
        await publicClient.waitForTransactionReceipt({ hash: approveUSDCTx });
      }

      if (vethAllowance < swapAmount) {
        const approveVETHTx = await walletClient.writeContract({
          address: c.mockVETH.address,
          abi: c.mockVETH.abi as any,
          functionName: 'approve',
          args: [c.poolSwapTest.address, parseUnits('1000', 18)]
        });
        await publicClient.waitForTransactionReceipt({ hash: approveVETHTx });
      }
      
      console.log('✅ Tokens approved');
    }

    // Test each case
    for (const testCase of testCases) {
      console.log(`\n🧪 Testing: ${testCase.name}`);
      
      try {
        const swapTx = await walletClient.writeContract({
          address: c.poolSwapTest.address,
          abi: c.poolSwapTest.abi as any,
          functionName: 'swap',
          args: [poolKey, swapParams, testSettings, testCase.hookData]
        });

        console.log('⏳ Transaction submitted:', swapTx);
        
        const receipt = await publicClient.waitForTransactionReceipt({ hash: swapTx });
        console.log('✅ Swap successful!');
        console.log('   Gas used:', receipt.gasUsed.toString());
        
      } catch (error) {
        console.log('❌ Swap failed:', error instanceof Error ? error.message.split('\n')[0] : 'Unknown error');
        
        // Try to decode the error if it's a WrappedError
        if (error instanceof Error && error.message.includes('0x90bfb865')) {
          console.log('   This is the "Invalid market" error from PositionFactory');
        }
      }
    }

    console.log('\n✨ Test Summary:');
    console.log('  📊 This test helps us understand what level of the stack is failing');
    console.log('  🔍 Empty hookData should bypass position creation entirely');
    console.log('  🚫 Invalid operation should trigger hook validation but not position logic');

  } catch (error) {
    console.error('❌ Error in swap test:', error);
    throw error;
  }
}

if (import.meta.main) {
  main().catch(console.error);
}
