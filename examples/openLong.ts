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
  CLOSE_LONG: 2,
  CLOSE_SHORT: 3,
  ADD_MARGIN: 4,
  REMOVE_MARGIN: 5
} as const;

async function main() {
  console.log('📈 Opening Long Position via Uniswap V4 PoolSwapTest + PerpsHook');
  
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
  console.log('🔗 RPC URL:', RPC_URL);

  // Build poolKey struct for VETH-USDC pair  
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

  // Generate poolId (matches how Uniswap V4 generates pool IDs)
  const poolKeyEncoded = encodeAbiParameters(
    [
      { name: 'currency0', type: 'address' },
      { name: 'currency1', type: 'address' },
      { name: 'fee', type: 'uint24' },
      { name: 'tickSpacing', type: 'int24' },
      { name: 'hooks', type: 'address' }
    ],
    [currency0 as `0x${string}`, currency1 as `0x${string}`, fee, tickSpacing, hooks]
  );
  const poolId = keccak256(poolKeyEncoded);

  console.log('🆔 Pool ID:', poolId);

  // Position parameters
  const marginAmount = parseUnits(process.argv[2] || '100', 6); // Default 100 USDC
  const positionSize = parseUnits(process.argv[3] || '0.1', 18); // Default 0.1 VETH
  const slippageBps = 500n; // 5% slippage tolerance

  console.log('📊 Position Parameters:');
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

    // Check current margin in margin account
    const currentMargin = (await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'getTotalBalance',
      args: [account.address]
    })) as bigint;

    console.log('🏦 Current Margin in Account:', formatUnits(currentMargin, 6), 'USDC');

    // Calculate poolId using the same method as Uniswap V4
    // PoolId = keccak256(abi.encode(poolKey))
    const poolKeyEncoded = encodeAbiParameters(
      [
        { type: 'address', name: 'currency0' },
        { type: 'address', name: 'currency1' },
        { type: 'uint24', name: 'fee' },
        { type: 'int24', name: 'tickSpacing' },
        { type: 'address', name: 'hooks' }
      ],
      [currency0, currency1, fee, tickSpacing, hooks]
    );
    const poolIdBytes32 = keccak256(poolKeyEncoded);
    
    console.log('🆔 Pool ID (calculated):', poolIdBytes32);

    // Force market registration to ensure both MarketManager and PositionFactory have it
    console.log('📝 Ensuring market is properly registered in both components...');
    
    try {
      // Register the market (requires owner privileges)
      const addMarketTx = await walletClient.writeContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: 'addMarket',
        args: [
          poolIdBytes32,          // marketId 
          currency0.toLowerCase() === c.mockVETH.address.toLowerCase() ? c.mockVETH.address : c.mockUSDC.address, // baseAsset (VETH)
          currency0.toLowerCase() === c.mockVETH.address.toLowerCase() ? c.mockUSDC.address : c.mockVETH.address, // quoteAsset (USDC) 
          c.poolManager.address   // poolAddress
        ]
      });
      
      console.log('⏳ Waiting for market registration...');
      await publicClient.waitForTransactionReceipt({ hash: addMarketTx });
      console.log('✅ Market registered successfully in both components');
    } catch (error) {
      console.log('ℹ️  Market may already exist, continuing...');
    }

    // Approve USDC for margin account if needed
    const marginAllowance = (await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'allowance',
      args: [account.address, c.marginAccount.address]
    })) as bigint;

    if (marginAllowance < marginAmount) {
      console.log('🔓 Approving USDC for MarginAccount...');
      const approveTx = await walletClient.writeContract({
        address: c.mockUSDC.address,
        abi: c.mockUSDC.abi as any,
        functionName: 'approve',
        args: [c.marginAccount.address, marginAmount]
      });
      
      console.log('⏳ Waiting for approval confirmation...');
      await publicClient.waitForTransactionReceipt({ hash: approveTx });
      console.log('✅ USDC approved for MarginAccount');
    }

    // Deposit margin if needed
    if (currentMargin < marginAmount) {
      console.log('💰 Depositing margin...');
      const depositTx = await walletClient.writeContract({
        address: c.marginAccount.address,
        abi: c.marginAccount.abi as any,
        functionName: 'deposit',
        args: [marginAmount]
      });
      
      await publicClient.waitForTransactionReceipt({ hash: depositTx });
      console.log('✅ Margin deposited');
    }

    // Approve USDC for PerpsHook (hook needs to transfer margin for positions)
    const hookAllowance = (await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'allowance',
      args: [account.address, c.perpsHook.address]
    })) as bigint;

    if (hookAllowance < marginAmount) {
      console.log('🔓 Approving USDC for PerpsHook...');
      const hookApproveTx = await walletClient.writeContract({
        address: c.mockUSDC.address,
        abi: c.mockUSDC.abi as any,
        functionName: 'approve',
        args: [c.perpsHook.address, marginAmount]
      });
      
      await publicClient.waitForTransactionReceipt({ hash: hookApproveTx });
      console.log('✅ USDC approved for PerpsHook');
    }

    // Get current market price
    try {
      const marketPrice = (await publicClient.readContract({
        address: c.perpsHook.address,
        abi: c.perpsHook.abi as any,
        functionName: 'getMarkPrice',
        args: [poolId]
      })) as bigint;
      
      console.log('📊 Current Mark Price:', formatUnits(marketPrice, 18), 'USDC per VETH');
    } catch (error) {
      console.log('ℹ️  Could not fetch market price - checking if market exists');
      
      // Check if market exists by trying to get market state
      try {
        const marketState = (await publicClient.readContract({
          address: c.perpsHook.address,
          abi: c.perpsHook.abi as any,
          functionName: 'getMarketState',
          args: [poolId]
        })) as any;
        
        console.log('📊 Market State:');
        console.log('  Is Active:', marketState.isActive);
        console.log('  Virtual Base:', formatUnits(marketState.virtualBase, 18));
        console.log('  Virtual Quote:', formatUnits(marketState.virtualQuote, 18));
      } catch (marketError) {
        console.log('❌ Market does not exist for this pool. Pool may need to be initialized first.');
        throw new Error('Market not found for pool ID: ' + poolId);
      }
    }

    // Prepare minimal swap for triggering the hook (very small amount)
    const swapAmount = parseUnits('0.001', 18); // Small swap amount
    
    // Approve tokens for the swap (to PoolSwapTest contract)
    const token0 = currency0.toLowerCase() === c.mockVETH.address.toLowerCase() ? c.mockVETH : c.mockUSDC;
    const swapAllowance = (await publicClient.readContract({
      address: token0.address,
      abi: token0.abi as any,
      functionName: 'allowance',
      args: [account.address, c.poolSwapTest.address]
    })) as bigint;

    if (swapAllowance < swapAmount) {
      console.log('🔓 Approving tokens for swap...');
      const swapApproveTx = await walletClient.writeContract({
        address: token0.address,
        abi: token0.abi as any,
        functionName: 'approve',
        args: [c.poolSwapTest.address, swapAmount]
      });
      
      await publicClient.waitForTransactionReceipt({ hash: swapApproveTx });
      console.log('✅ Swap tokens approved');
    }

    // Prepare TradeParams for hookData (matching PerpsHook.TradeParams struct)
    const tradeParams = {
      operation: TRADE_OPERATIONS.OPEN_LONG,
      tokenId: 0n, // New position
      size: positionSize,
      margin: marginAmount,
      maxSlippage: slippageBps,
      trader: account.address
    };

    // Encode hookData using the exact structure from PerpsHook
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

    console.log('🔄 Opening long position via PoolSwapTest + PerpsHook...');

    // Prepare swap parameters for the actual swap
    const swapParams = {
      zeroForOne: true, // Swap currency0 for currency1
      amountSpecified: -Number(swapAmount), // Negative for exact input swap
      sqrtPriceLimitX96: 4295128740n // Very permissive price limit
    };

    // Pool key for the swap
    const poolKey = {
      currency0: currency0 as `0x${string}`,
      currency1: currency1 as `0x${string}`,
      fee,
      tickSpacing,
      hooks: hooks as `0x${string}`
    };

    // Test settings for PoolSwapTest
    const testSettings = {
      takeClaims: false,
      settleUsingBurn: false
    };

    // Execute the swap through PoolSwapTest which will trigger our PerpsHook
    const txHash = await walletClient.writeContract({
      address: c.poolSwapTest.address,
      abi: c.poolSwapTest.abi as any,
      functionName: 'swap',
      args: [poolKey, swapParams, testSettings, hookData]
    });

    console.log('⏳ Waiting for transaction confirmation...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
    
    console.log('✅ Position opened successfully!');
    console.log('📋 Transaction Hash:', txHash);
    console.log('📦 Block Number:', receipt.blockNumber);
    console.log('⛽ Gas Used:', receipt.gasUsed);

    // Get updated margin balance
    const updatedMargin = (await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'getTotalBalance',
      args: [account.address]
    })) as bigint;

    console.log('🏦 Updated Margin in Account:', formatUnits(updatedMargin, 6), 'USDC');

    // Get market state after position opening
    try {
      const marketState = (await publicClient.readContract({
        address: c.perpsHook.address,
        abi: c.perpsHook.abi as any,
        functionName: 'getMarketState',
        args: [poolId]
      })) as any;
      
      console.log('📊 Market State After Trade:');
      console.log('  Total Long OI:', formatUnits(marketState.totalLongOI, 18), 'VETH');
      console.log('  Total Short OI:', formatUnits(marketState.totalShortOI, 18), 'VETH');
      console.log('  Virtual Base:', formatUnits(marketState.virtualBase, 18));
      console.log('  Virtual Quote:', formatUnits(marketState.virtualQuote, 18));
      
      // Get current mark price after trade
      const newMarkPrice = (await publicClient.readContract({
        address: c.perpsHook.address,
        abi: c.perpsHook.abi as any,
        functionName: 'getMarkPrice',
        args: [poolId]
      })) as bigint;
      
      console.log('📊 New Mark Price:', formatUnits(newMarkPrice, 18), 'USDC per VETH');
      
      const notionalValue = (Number(formatUnits(positionSize, 18)) * Number(formatUnits(newMarkPrice, 18))).toFixed(2);
      console.log('💵 Position Notional Value:', notionalValue, 'USDC');
      
    } catch (error) {
      console.log('ℹ️  Could not fetch market state - position may still be opened');
    }

    console.log('🎉 Long position opened successfully via PoolSwapTest + PerpsHook!');
    
  } catch (error) {
    console.error('❌ Error opening position:', error);
    throw error;
  }
}

// Execute with error handling
main().catch(e => { 
  console.error('💥 Failed to open position:', e); 
  process.exit(1); 
});
