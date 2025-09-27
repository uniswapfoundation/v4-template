// Open a short position using Uniswap SwapRouter with PerpsHook integration
import 'dotenv/config';
import { http, createWalletClient, createPublicClient, parseUnits, defineChain, formatUnits, encodeAbiParameters, keccak256, parseAbiParameters } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';
import { calculateUsdcVethPoolId, getPoolInfo } from './poolUtils';

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
  console.log('📉 Opening Short Position via PoolSwapTest + PerpsHook');
  
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

  // Calculate pool ID and configuration dynamically
  const poolId = calculateUsdcVethPoolId(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);
  const poolInfo = getPoolInfo(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);
  
  console.log('💱 Pool Configuration:');
  console.log('  Currency0 (lower):', poolInfo.poolKey.currency0);
  console.log('  Currency1 (higher):', poolInfo.poolKey.currency1);
  console.log('  Fee:', poolInfo.poolKey.fee, 'bps');
  console.log('  Hook:', poolInfo.poolKey.hooks);
  console.log('  Base Asset (VETH):', poolInfo.baseAsset);
  console.log('  Quote Asset (USDC):', poolInfo.quoteAsset);
  console.log('🆔 Pool ID:', poolId);
  
  // Extract values for easier reference
  const currency0 = poolInfo.poolKey.currency0;
  const currency1 = poolInfo.poolKey.currency1;
  const fee = poolInfo.poolKey.fee;
  const tickSpacing = poolInfo.poolKey.tickSpacing;
  const hooks = poolInfo.poolKey.hooks;

  // Position parameters (can be customized via command line)
  const marginAmount = parseUnits(process.argv[2] || '1000', 6); // Default 1000 USDC
  const positionSize = parseUnits(process.argv[3] || '1', 18); // Default 1 VETH
  const slippageBps = 500n; // 5% slippage tolerance

  console.log('📊 Short Position Parameters:');
  console.log('  Margin:', formatUnits(marginAmount, 6), 'USDC');
  console.log('  Position Size:', formatUnits(positionSize, 18), 'VETH');
  console.log('  Slippage:', Number(slippageBps) / 100, '%');

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

    // Check and approve USDC allowance for PerpsHook (hook handles margin transfers)
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
      
      console.log('⏳ Waiting for approval confirmation...');
      await publicClient.waitForTransactionReceipt({ hash: approveTx });
      console.log('✅ USDC approved for hook');
    }

    // Approve tokens for PoolSwapTest with proper decimals
    console.log('🔓 Approving tokens for PoolSwapTest...');
    
    // Approve both tokens with proper decimals
    const usdcApproveAmount = parseUnits('1000', 6); // USDC has 6 decimals
    const vethApproveAmount = parseUnits('1000', 18); // VETH has 18 decimals

    // Approve USDC
    const usdcApproveTx = await walletClient.writeContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'approve',
      args: [c.poolSwapTest.address, usdcApproveAmount]
    });
    await publicClient.waitForTransactionReceipt({ hash: usdcApproveTx });

    // Approve VETH
    const vethApproveTx = await walletClient.writeContract({
      address: c.mockVETH.address,
      abi: c.mockVETH.abi as any,
      functionName: 'approve',
      args: [c.poolSwapTest.address, vethApproveAmount]
    });
    await publicClient.waitForTransactionReceipt({ hash: vethApproveTx });
    console.log('✅ Tokens approved for PoolSwapTest');

    // Prepare TradeParams for hookData (short position)
    const tradeParams = {
      operation: TRADE_OPERATIONS.OPEN_SHORT,
      tokenId: 0n, // New position
      size: positionSize,
      margin: marginAmount,
      maxSlippage: slippageBps,
      trader: account.address
    };

    // Encode hookData using the same structure as in tests
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

    console.log('🔄 Opening short position via PoolSwapTest + PerpsHook...');

    // Prepare pool key
    const poolKey = {
      currency0,
      currency1,
      fee,
      tickSpacing,
      hooks
    };

    // Prepare swap parameters - for short position, swap in opposite direction
    const swapAmount = parseUnits('0.001', 18); // Very small swap amount to trigger hook
    const swapParams = {
      zeroForOne: false, // Swap currency1 for currency0 (opposite of long)
      amountSpecified: swapAmount, // Small amount
      sqrtPriceLimitX96: 1461446703485210103287273052203988822378723970341n // Permissive price limit for reverse swap
    };

    // Test settings for PoolSwapTest
    const testSettings = {
      takeClaims: false,
      settleUsingBurn: false
    };

    // Execute swap via PoolSwapTest with hookData
    const txHash = await walletClient.writeContract({
      address: c.poolSwapTest.address,
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
    
    console.log('✅ Short position opened successfully via PoolSwapTest!');
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

    // Calculate pool ID for getting mark price
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

    // Try to get position information from PerpsHook
    try {
      console.log('📊 Fetching position details from hook...');
      
      // Get mark price from hook
      const markPrice = (await publicClient.readContract({
        address: c.perpsHook.address,
        abi: [
          {
            "inputs": [{"name": "poolId", "type": "bytes32"}],
            "name": "getMarkPrice",
            "outputs": [{"name": "", "type": "uint256"}],
            "stateMutability": "view",
            "type": "function"
          }
        ],
        functionName: 'getMarkPrice',
        args: [poolId]
      })) as bigint;
      
      console.log('📊 Current Mark Price:', formatUnits(markPrice, 18), 'USDC per VETH');
      
      const notionalValue = (Number(formatUnits(positionSize, 18)) * Number(formatUnits(markPrice, 18))).toFixed(2);
      console.log('💵 Position Notional Value:', notionalValue, 'USDC');
      
      // Get market state to show open interest
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
      console.log('ℹ️  Could not fetch detailed position info from hook');
    }

    console.log('🎉 Short position opened successfully via Uniswap SwapRouter + PerpsHook!');
    console.log('📝 Note: Short position benefits from price decreases');
    console.log('📝 Position is opened through hook integration during swap execution');
    
  } catch (error) {
    console.error('❌ Error opening short position:', error);
    throw error;
  }
}

// Execute with error handling
main().catch(e => { 
  console.error('💥 Failed to open short position:', e); 
  process.exit(1); 
});
