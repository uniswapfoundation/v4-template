// Close a position using Uniswap SwapRouter with PerpsHook integration
import 'dotenv/config';
import { http, createWalletClient, createPublicClient, parseUnits, defineChain, formatUnits, encodeAbiParameters, keccak256 } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

// Trade operation types (matching PerpsHook.TradeParams)
const TRADE_OPERATIONS = {
  OPEN_LONG: 0,
  OPEN_SHORT: 1,
  CLOSE_POSITION: 2,
  ADD_MARGIN: 3,
  REMOVE_MARGIN: 4,
  LIQUIDATE: 5
} as const;

// PoolSwapTest ABI (for testing swaps with hooks)
const POOL_SWAP_TEST_ABI = [
  {
    "inputs": [
      {
        "components": [
          {"name": "currency0", "type": "address"},
          {"name": "currency1", "type": "address"},
          {"name": "fee", "type": "uint24"},
          {"name": "tickSpacing", "type": "int24"},
          {"name": "hooks", "type": "address"}
        ],
        "name": "key",
        "type": "tuple"
      },
      {
        "components": [
          {"name": "zeroForOne", "type": "bool"},
          {"name": "amountSpecified", "type": "int256"},
          {"name": "sqrtPriceLimitX96", "type": "uint160"}
        ],
        "name": "params", 
        "type": "tuple"
      },
      {
        "components": [
          {"name": "takeClaims", "type": "bool"},
          {"name": "settleUsingBurn", "type": "bool"}
        ],
        "name": "testSettings",
        "type": "tuple"
      },
      {"name": "hookData", "type": "bytes"}
    ],
    "name": "swap",
    "outputs": [{"name": "delta", "type": "int256"}],
    "stateMutability": "payable",
    "type": "function"
  }
] as const;

async function main() {
  console.log('📉 Closing Position via PoolSwapTest + PerpsHook');
  
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

  // Position parameters
  const positionTokenId = process.argv[2]; // Position NFT token ID
  if (!positionTokenId) {
    throw new Error('Position token ID required as first argument');
  }

  const slippageBps = BigInt(process.argv[3] || '500'); // Default 5% slippage

  console.log('📊 Close Position Parameters:');
  console.log('  Position Token ID:', positionTokenId);
  console.log('  Slippage:', Number(slippageBps) / 100, '%');

  // Build poolKey struct for VETH-USDC pair
  const fee = 3000; // 0.3%
  const tickSpacing = 60;
  const hooks = c.perpsHook.address;
  
  // Order currencies by address (lower address = currency0)
  const [currency0, currency1] = c.mockUSDC.address.toLowerCase() < c.mockVETH.address.toLowerCase()
    ? [c.mockUSDC.address, c.mockVETH.address]
    : [c.mockVETH.address, c.mockUSDC.address];

  try {
    // Check current margin before closing
    const currentMargin = (await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'getMargin',
      args: [account.address]
    })) as bigint;

    console.log('🏦 Current Margin in Account:', formatUnits(currentMargin, 6), 'USDC');

    // Check if user owns the position NFT
    try {
      const positionOwner = (await publicClient.readContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: 'ownerOf',
        args: [BigInt(positionTokenId)]
      })) as string;

      if (positionOwner.toLowerCase() !== account.address.toLowerCase()) {
        throw new Error(`Position ${positionTokenId} is not owned by ${account.address}. Owner: ${positionOwner}`);
      }
      
      console.log('✅ Position ownership confirmed');
    } catch (error) {
      console.log('ℹ️  Could not verify position ownership - proceeding with close attempt');
    }

    // Approve tokens for PoolSwapTest (small amount for the swap)
    const swapAmount = parseUnits('0.001', 18); // Small swap amount
    const swapTestAddress = "0x9140a78c1a137c7ff1c151ec8231272af78a99a4"; // From deployments.json
    
    const tokenToApprove = currency0.toLowerCase() === c.mockVETH.address.toLowerCase() ? c.mockVETH : c.mockUSDC;
    const swapAllowance = (await publicClient.readContract({
      address: tokenToApprove.address,
      abi: tokenToApprove.abi as any,
      functionName: 'allowance',
      args: [account.address, swapTestAddress]
    })) as bigint;

    if (swapAllowance < swapAmount) {
      console.log('🔓 Approving tokens for PoolSwapTest...');
      const swapApproveTx = await walletClient.writeContract({
        address: tokenToApprove.address,
        abi: tokenToApprove.abi as any,
        functionName: 'approve',
        args: [swapTestAddress, swapAmount]
      });
      
      await publicClient.waitForTransactionReceipt({ hash: swapApproveTx });
      console.log('✅ Swap tokens approved');
    }

    // Prepare TradeParams for hookData to close position
    const tradeParams = {
      operation: TRADE_OPERATIONS.CLOSE_POSITION,
      tokenId: BigInt(positionTokenId),
      size: 0n, // Not used for close operation
      margin: 0n, // Not used for close operation
      maxSlippage: slippageBps,
      trader: account.address
    };

    // Encode hookData
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

    console.log('🔄 Closing position via PoolSwapTest + PerpsHook...');

    // Prepare pool key
    const poolKey = {
      currency0,
      currency1,
      fee,
      tickSpacing,
      hooks
    };

    // Prepare swap parameters - minimal swap to trigger hook
    const swapParams = {
      zeroForOne: false, // Reverse swap for closing
      amountSpecified: BigInt(swapAmount),
      sqrtPriceLimitX96: 1461446703485210103287273052203988822378723970341n // Permissive limit for reverse
    };

    // Test settings for PoolSwapTest
    const testSettings = {
      takeClaims: false,
      settleUsingBurn: false
    };

    // Execute swap via PoolSwapTest with hookData
    const txHash = await walletClient.writeContract({
      address: swapTestAddress as `0x${string}`,
      abi: POOL_SWAP_TEST_ABI,
      functionName: 'swap',
      args: [
        poolKey,
        swapParams,
        testSettings,
        hookData
      ]
    });

    console.log('⏳ Waiting for transaction confirmation...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
    
    console.log('✅ Position closed successfully via PoolSwapTest!');
    console.log('📋 Transaction Hash:', txHash);
    console.log('📦 Block Number:', receipt.blockNumber);

    // Get updated margin balance
    const updatedMargin = (await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'getMargin',
      args: [account.address]
    })) as bigint;

    console.log('🏦 Updated Margin in Account:', formatUnits(updatedMargin, 6), 'USDC');
    
    // Calculate realized PnL
    const marginDifference = updatedMargin - currentMargin;
    if (marginDifference > 0n) {
      console.log('💰 Realized Profit:', formatUnits(marginDifference, 6), 'USDC');
    } else if (marginDifference < 0n) {
      console.log('📉 Realized Loss:', formatUnits(-marginDifference, 6), 'USDC');
    } else {
      console.log('🔄 Break-even position');
    }

    // Get updated USDC balance
    const usdcBalance = (await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    })) as bigint;

    console.log('💳 Updated USDC Balance:', formatUnits(usdcBalance, 6));

    // Calculate pool ID and check market state
    const poolId = keccak256(
      encodeAbiParameters(
        [
          {
            type: 'tuple',
            components: [
              { name: 'currency0', type: 'address' },
              { name: 'currency1', type: 'address' },
              { name: 'fee', type: 'uint24' },
              { name: 'tickSpacing', type: 'int24' },
              { name: 'hooks', type: 'address' }
            ]
          }
        ],
        [poolKey]
      )
    );

    // Get updated market state
    try {
      const marketState = (await publicClient.readContract({
        address: c.perpsHook.address,
        abi: [
          {
            "inputs": [{"name": "poolId", "type": "bytes32"}],
            "name": "getMarketState",
            "outputs": [
              {
                "components": [
                  {"name": "isActive", "type": "bool"},
                  {"name": "virtualBase", "type": "uint256"},
                  {"name": "virtualQuote", "type": "uint256"},
                  {"name": "k", "type": "uint256"},
                  {"name": "globalFundingIndex", "type": "int256"},
                  {"name": "totalLongOI", "type": "uint256"},
                  {"name": "totalShortOI", "type": "uint256"},
                  {"name": "maxOICap", "type": "uint256"},
                  {"name": "lastFundingTime", "type": "uint256"}
                ],
                "type": "tuple"
              }
            ],
            "stateMutability": "view",
            "type": "function"
          }
        ],
        functionName: 'getMarketState',
        args: [poolId]
      })) as any;
      
      console.log('📈 Total Long Open Interest:', formatUnits(marketState.totalLongOI, 18), 'VETH');
      console.log('📉 Total Short Open Interest:', formatUnits(marketState.totalShortOI, 18), 'VETH');
      
    } catch (error) {
      console.log('ℹ️  Could not fetch market state after close');
    }

    console.log('🎉 Position closed successfully via Uniswap SwapRouter + PerpsHook!');
    console.log('📝 Note: Position was closed through hook integration during swap execution');
    
  } catch (error) {
    console.error('❌ Error closing position:', error);
    throw error;
  }
}

// Execute with error handling
main().catch(e => { 
  console.error('💥 Failed to close position:', e); 
  process.exit(1); 
});
