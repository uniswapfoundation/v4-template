// Open a long position using Uniswap PoolSwapTest with hookData
// This approach mimics the test pattern where positions are opened through swaps with hookData
import 'dotenv/config';
import { http, createWalletClient, createPublicClient, parseUnits, defineChain, formatUnits, encodeAbiParameters } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

// Position operation types matching the PerpsHook
enum OperationType {
  OPEN_LONG = 0,
  OPEN_SHORT = 1,
  CLOSE_POSITION = 2,
  ADD_MARGIN = 3,
  REMOVE_MARGIN = 4,
  LIQUIDATE = 5
}

interface TradeParams {
  operation: number;
  tokenId: bigint;
  size: bigint;
  margin: bigint;
  maxSlippage: bigint;
  trader: `0x${string}`;
}

async function main() {
  console.log('📈 Opening Long Position via Uniswap Swap with hookData');
  
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
  console.log('🌐 Chain ID:', CHAIN_ID);

  // Position parameters (can be customized via command line) - start with very small amounts for testing
  const marginAmount = parseUnits(process.argv[2] || '50', 6); // Default 50 USDC (very small for testing)
  const positionSize = parseUnits(process.argv[3] || '0.01', 18); // Default 0.01 VETH (very small for testing)
  const maxSlippage = BigInt(process.argv[4] || '1000'); // Default 10% = 1000 bps (generous)

  console.log('📊 Position Parameters:');
  console.log('  Margin:', formatUnits(marginAmount, 6), 'USDC');
  console.log('  Size:', formatUnits(positionSize, 18), 'VETH');
  console.log('  Max Slippage:', Number(maxSlippage) / 100, '%');

  // Build pool key for VETH-USDC pair
  const fee = 3000; // 0.3%
  const tickSpacing = 60;
  const hooks = c.perpsHook.address;
  
  // Order currencies by address (lower address = currency0)
  const [currency0, currency1] = c.mockUSDC.address.toLowerCase() < c.mockVETH.address.toLowerCase()
    ? [c.mockUSDC.address, c.mockVETH.address]
    : [c.mockVETH.address, c.mockUSDC.address];

  console.log('💱 Pool Configuration:');
  console.log('  Currency0:', currency0);
  console.log('  Currency1:', currency1);
  console.log('  Fee:', fee, 'bps');
  console.log('  Hook:', hooks);

  try {
    // Check current USDC balance
    const usdcBalance = (await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    })) as bigint;

    console.log('💳 Current USDC Balance:', formatUnits(usdcBalance, 6));

    if (usdcBalance < marginAmount) {
      throw new Error(`Insufficient USDC balance. Need: ${formatUnits(marginAmount, 6)}, Have: ${formatUnits(usdcBalance, 6)}`);
    }

    // Check margin account balance
    const currentMargin = (await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'getTotalBalance',
      args: [account.address]
    })) as bigint;

    console.log('🏦 Current Margin in Account:', formatUnits(currentMargin, 6), 'USDC');

    // Deposit margin if needed
    if (currentMargin < marginAmount) {
      const neededMargin = marginAmount - currentMargin;
      console.log('🏦 Need to deposit margin:', formatUnits(neededMargin, 6), 'USDC');

      // Approve USDC for MarginAccount
      const marginAllowance = (await publicClient.readContract({
        address: c.mockUSDC.address,
        abi: c.mockUSDC.abi as any,
        functionName: 'allowance',
        args: [account.address, c.marginAccount.address]
      })) as bigint;

      if (marginAllowance < neededMargin) {
        console.log('🔓 Approving USDC for MarginAccount...');
        const approveTx = await walletClient.writeContract({
          address: c.mockUSDC.address,
          abi: c.mockUSDC.abi as any,
          functionName: 'approve',
          args: [c.marginAccount.address, neededMargin]
        });
        
        await publicClient.waitForTransactionReceipt({ hash: approveTx });
        console.log('✅ USDC approved for MarginAccount');
      }

      // Deposit margin
      console.log('🔄 Depositing margin...');
      const depositTx = await walletClient.writeContract({
        address: c.marginAccount.address,
        abi: c.marginAccount.abi as any,
        functionName: 'deposit',
        args: [neededMargin]
      });
      
      await publicClient.waitForTransactionReceipt({ hash: depositTx });
      console.log('✅ Margin deposited');
    }

    // Approve USDC for PerpsHook (for potential fees)
    const hookAllowance = (await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'allowance',
      args: [account.address, c.perpsHook.address]
    })) as bigint;

    if (hookAllowance < marginAmount) {
      console.log('🔓 Approving USDC for PerpsHook...');
      const approveTx = await walletClient.writeContract({
        address: c.mockUSDC.address,
        abi: c.mockUSDC.abi as any,
        functionName: 'approve',
        args: [c.perpsHook.address, marginAmount]
      });
      
      await publicClient.waitForTransactionReceipt({ hash: approveTx });
      console.log('✅ USDC approved for PerpsHook');
    }

    // Approve tokens for PoolSwapTest
    console.log('🔓 Approving tokens for PoolSwapTest...');
    
    // Approve both tokens for the swap test contract
    const amount0ToApprove = parseUnits('1000', currency0 === c.mockUSDC.address ? 6 : 18);
    const amount1ToApprove = parseUnits('1000', currency1 === c.mockUSDC.address ? 6 : 18);

    const token0ApproveTx = await walletClient.writeContract({
      address: currency0 as `0x${string}`,
      abi: c.mockUSDC.abi as any, // Use USDC ABI (works for both ERC20 tokens)
      functionName: 'approve',
      args: [c.poolSwapTest.address, amount0ToApprove]
    });
    await publicClient.waitForTransactionReceipt({ hash: token0ApproveTx });

    const token1ApproveTx = await walletClient.writeContract({
      address: currency1 as `0x${string}`,
      abi: c.mockUSDC.abi as any,
      functionName: 'approve',
      args: [c.poolSwapTest.address, amount1ToApprove]
    });
    await publicClient.waitForTransactionReceipt({ hash: token1ApproveTx });
    console.log('✅ Tokens approved for PoolSwapTest');

    // Prepare trade parameters for hookData
    const tradeParams: TradeParams = {
      operation: OperationType.OPEN_LONG,
      tokenId: 0n, // New position
      size: positionSize,
      margin: marginAmount,
      maxSlippage: maxSlippage,
      trader: account.address
    };

    // Encode hookData using the same structure as tests (abi.encode)
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

    console.log('📦 Hook data encoded');

    // Prepare swap parameters
    const poolKey = {
      currency0: currency0 as `0x${string}`,
      currency1: currency1 as `0x${string}`,
      fee,
      tickSpacing,
      hooks: hooks as `0x${string}`
    };

    // Use the exact same parameters as the working test
    const swapAmount = parseUnits('0.01', 18); // 0.01 ether - same as test
    
    // The pool is at SQRT_PRICE_1_1, so we need a LOWER limit for zeroForOne
    // Use SQRT_PRICE_1_4 which is much lower than current price
    const sqrtPriceLimitX96 = "39614081257132168796771975168"; // SQRT_PRICE_1_4 - much lower than current

    const swapParams = {
      zeroForOne: true, // Swap token0 for token1
      amountSpecified: swapAmount,
      sqrtPriceLimitX96: BigInt(sqrtPriceLimitX96)
    };

    const testSettings = {
      takeClaims: false,
      settleUsingBurn: false
    };

    console.log('🔄 Executing swap with hookData to open long position...');
    
    // Execute swap through PoolSwapTest which will trigger our hook
    const swapTx = await walletClient.writeContract({
      address: c.poolSwapTest.address,
      abi: c.poolSwapTest.abi as any,
      functionName: 'swap',
      args: [poolKey, swapParams, testSettings, hookData]
    });

    console.log('⏳ Waiting for transaction confirmation...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash: swapTx });
    
    console.log('✅ Swap executed successfully!');
    console.log('📋 Transaction Hash:', swapTx);
    console.log('📦 Block Number:', receipt.blockNumber);

    // Get updated margin balance
    const updatedMargin = (await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'getTotalBalance',
      args: [account.address]
    })) as bigint;

    console.log('🏦 Updated Margin in Account:', formatUnits(updatedMargin, 6), 'USDC');

    // Try to get position information
    try {
      console.log('📊 Fetching position details...');
      
      // Check if user has any position NFTs
      const positionBalance = (await publicClient.readContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: 'balanceOf',
        args: [account.address]
      })) as bigint;

      if (positionBalance > 0n) {
        console.log('🎯 Position NFTs owned:', positionBalance.toString());
        
        // Get the token ID of the latest position
        const tokenId = (await publicClient.readContract({
          address: c.positionManager.address,
          abi: c.positionManager.abi as any,
          functionName: 'tokenOfOwnerByIndex',
          args: [account.address, positionBalance - 1n]
        })) as bigint;

        console.log('🏷️  Latest Position Token ID:', tokenId.toString());
      } else {
        console.log('ℹ️  No position NFTs found');
      }
    } catch (error) {
      console.log('ℹ️  Could not fetch position details');
    }

    console.log('🎉 Long position opened via swap successfully!');
    
  } catch (error) {
    console.error('❌ Error opening position via swap:', error);
    throw error;
  }
}

// Execute with error handling
main().catch(e => { 
  console.error('💥 Failed to open position via swap:', e); 
  process.exit(1); 
});
