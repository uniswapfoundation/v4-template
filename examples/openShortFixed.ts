import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';
import { calculateUsdcVethPoolId, getPoolInfo } from './poolUtils';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

// Get command line arguments
const args = process.argv.slice(2);
if (args.length < 2) {
  console.log('Usage: bun run openShortCorrectCalculation.ts <marginAmount> <leverage>');
  console.log('Example: bun run openShortCorrectCalculation.ts 150 3  # Short with 150 USDC margin at 3x leverage');
  console.log('Note: Minimum margin appears to be ~100 USDC for most position sizes');
  process.exit(1);
}

const marginAmount = parseFloat(args[0]!);
const leverage = parseFloat(args[1]!);

// Validate minimum margin
if (marginAmount < 100) {
  console.log('⚠️  Warning: Margin less than 100 USDC may fail due to InsufficientMargin error');
  console.log('💡 Try using at least 100 USDC margin');
}

async function openShortPosition() {
  console.log('📉 Opening Short Position with Correct Calculations');
  
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

  // Calculate pool ID dynamically
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

  console.log('📊 Position Parameters:');
  console.log('  Margin:', marginAmount, 'USDC');
  console.log('  Leverage:', leverage, 'x');

  try {
    // Get current mark price
    const markPrice = await publicClient.readContract({
      address: c.fundingOracle.address,
      abi: c.fundingOracle.abi as any,
      functionName: 'getMarkPrice',
      args: [poolId]
    }) as bigint;

    const markPriceFormatted = Number(markPrice) / 1e18;
    console.log('📊 Current Mark Price:', markPriceFormatted, 'USDC per VETH');

    // Calculate SHORT position size (negative for short)
    const notionalValue = marginAmount * leverage;
    const positionSizeVETH = notionalValue / markPriceFormatted;
    const positionSizeWei = BigInt(Math.floor(positionSizeVETH * 1e18));
    const shortPositionSizeWei = -positionSizeWei; // NEGATIVE for short positions

    console.log('📈 Expected Position Size:', positionSizeVETH.toFixed(6), 'VETH (SHORT)');
    console.log('💵 Expected Notional Value:', notionalValue.toFixed(2), 'USDC');
    console.log('🔢 Position Size Wei:', shortPositionSizeWei.toString());

    // Convert margin to wei (USDC has 6 decimals)
    const marginWei = BigInt(Math.floor(marginAmount * 1e6));
    console.log('🔢 Margin Wei:', marginWei.toString());

    // Check USDC balance
    const usdcBalance = await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    }) as bigint;

    console.log('💳 Current USDC Balance:', Number(usdcBalance) / 1e6);

    if (usdcBalance < marginWei) {
      throw new Error(`Insufficient USDC balance. Need ${marginAmount} USDC, have ${Number(usdcBalance) / 1e6} USDC`);
    }

    // Step 1: Approve USDC for MarginAccount
    console.log('💰 Depositing margin to MarginAccount for positioning...');
    
    const approveTx = await walletClient.writeContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'approve',
      args: [c.marginAccount.address, marginWei]
    });

    await publicClient.waitForTransactionReceipt({ hash: approveTx });
    console.log('✅ USDC approved for MarginAccount');

    // Step 2: Deposit margin to MarginAccount
    const depositTx = await walletClient.writeContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'deposit',
      args: [marginWei]
    });

    await publicClient.waitForTransactionReceipt({ hash: depositTx });
    console.log('✅ Margin deposited to MarginAccount');

    // Step 3: Open SHORT position via PositionManager
    console.log('🔄 Opening SHORT position via PositionManager...');
    
    const entryPriceWei = BigInt(Math.floor(markPriceFormatted * 1e18));
    
    console.log('📋 Position Manager Parameters:');
    console.log('  Market ID:', poolId);
    console.log('  Size Base:', shortPositionSizeWei.toString(), '(NEGATIVE for SHORT)');
    console.log('  Entry Price:', entryPriceWei.toString());
    console.log('  Margin:', marginWei.toString());

    const positionTx = await walletClient.writeContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi as any,
      functionName: 'openPosition',
      args: [poolId, shortPositionSizeWei, entryPriceWei, marginWei]
    });

    console.log('⏳ Waiting for position opening...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash: positionTx });
    
    console.log('🎉 SHORT Position opened successfully!');
    console.log('📋 Transaction Hash:', positionTx);
    console.log('📦 Block Number:', receipt.blockNumber);

    // Get the position ID from events or by checking recent positions
    // For now, let's try to find the new position
    console.log('\n🔍 Checking for new position...');
    
    // Check position IDs 1-10 to find the new one
    for (let i = 1; i <= 10; i++) {
      try {
        const position = await publicClient.readContract({
          address: c.positionManager.address,
          abi: c.positionManager.abi as any,
          functionName: 'getPosition',
          args: [BigInt(i)]
        }) as any;

        if (position.owner.toLowerCase() === account.address.toLowerCase() && 
            Number(position.sizeBase) < 0) { // Check for SHORT (negative size)
          console.log(`📊 Found new SHORT position #${i}:`);
          console.log(`  Size: ${Number(position.sizeBase) / 1e18} VETH (SHORT)`);
          console.log(`  Margin: ${Number(position.margin) / 1e6} USDC`);
          console.log(`  Entry Price: ${Number(position.entryPrice) / 1e18} USDC`);
          
          const leverage_actual = Math.abs(Number(position.sizeBase) / 1e18) * (Number(position.entryPrice) / 1e18) / (Number(position.margin) / 1e6);
          console.log(`  Actual Leverage: ${leverage_actual.toFixed(2)}x`);
          break;
        }
      } catch (e) {
        // Position doesn't exist, continue
      }
    }

  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  }
}

openShortPosition().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
