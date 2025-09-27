import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

// Get command line arguments
const args = process.argv.slice(2);
if (args.length < 2) {
  console.log('Usage: bun run removeMargin.ts <tokenId> <marginAmount>');
  console.log('Example: bun run removeMargin.ts 1 50   # Remove 50 USDC margin from position 1');
  process.exit(1);
}

const tokenId = BigInt(args[0]!);
const marginAmount = parseFloat(args[1]!);

async function removeMargin() {
  console.log('📉 Removing Margin from Position');
  
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
  console.log('🏷️  Position Token ID:', Number(tokenId));
  console.log('💰 Removing margin:', marginAmount, 'USDC');

  try {
    // Get position details first
    const position = await publicClient.readContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi as any,
      functionName: 'getPosition',
      args: [tokenId]
    }) as any;

    console.log('\n📊 Current Position:');
    const currentMargin = Number(position.margin) / 1e6;
    const sizeBase = Number(position.sizeBase) / 1e18;
    const entryPrice = Number(position.entryPrice) / 1e18;
    const isLong = Number(position.sizeBase) > 0;
    
    console.log(`  Current Margin: ${currentMargin} USDC`);
    console.log(`  Size: ${Math.abs(sizeBase)} VETH (${isLong ? 'LONG' : 'SHORT'})`);
    console.log(`  Entry Price: ${entryPrice} USDC per VETH`);

    // Verify ownership
    if (position.owner.toLowerCase() !== account.address.toLowerCase()) {
      throw new Error('You do not own this position');
    }

    // Validate margin removal
    if (marginAmount <= 0) {
      throw new Error('Margin amount must be positive');
    }

    if (marginAmount >= currentMargin) {
      throw new Error(`Cannot remove ${marginAmount} USDC - only ${currentMargin} USDC available`);
    }

    const newMargin = currentMargin - marginAmount;
    
    // Check if remaining margin is sufficient for position size
    const notionalValue = Math.abs(sizeBase) * entryPrice;
    const leverage = notionalValue / newMargin;
    
    console.log('\n📊 Margin Analysis:');
    console.log(`  Current Margin: ${currentMargin} USDC`);
    console.log(`  Removing: ${marginAmount} USDC`);
    console.log(`  New Margin: ${newMargin} USDC`);
    console.log(`  Position Notional: ${notionalValue.toFixed(2)} USDC`);
    console.log(`  New Leverage: ${leverage.toFixed(2)}x`);

    if (leverage > 10) {
      console.log('⚠️  Warning: New leverage will be', leverage.toFixed(2) + 'x');
      console.log('⚠️  This may put your position at risk of liquidation');
    }

    // Get current mark price for liquidation estimation
    const markPrice = await publicClient.readContract({
      address: c.fundingOracle.address,
      abi: c.fundingOracle.abi as any,
      functionName: 'getMarkPrice',
      args: ['0xdb86d006b7f5ba7afb160f08da976bf53d7254e25da80f1dda0a5d36d26d656d']
    }) as bigint;

    const markPriceFormatted = Number(markPrice) / 1e18;
    console.log(`📊 Current Mark Price: ${markPriceFormatted} USDC per VETH`);

    // Rough liquidation price estimation (simplified)
    let estimatedLiquidationPrice = 0;
    if (isLong) {
      // For longs: liquidation when position value + margin <= 0
      // Simplified: entryPrice - (newMargin / sizeAbs)
      estimatedLiquidationPrice = entryPrice - (newMargin / Math.abs(sizeBase));
    } else {
      // For shorts: liquidation when position value - margin >= 0
      // Simplified: entryPrice + (newMargin / sizeAbs)
      estimatedLiquidationPrice = entryPrice + (newMargin / Math.abs(sizeBase));
    }

    console.log(`📊 Estimated Liquidation Price: ${estimatedLiquidationPrice.toFixed(2)} USDC per VETH`);

    // Get free balance before
    const freeBalanceBefore = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'freeBalance',
      args: [account.address]
    }) as bigint;

    console.log(`\n💰 Free balance before: ${Number(freeBalanceBefore) / 1e6} USDC`);

    // Remove margin by calling withdrawMargin
    console.log('\n🔄 Removing margin...');
    
    const removeTx = await walletClient.writeContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi as any,
      functionName: 'withdrawMargin',
      args: [tokenId, BigInt(Math.floor(marginAmount * 1e6))]
    });

    console.log('⏳ Waiting for margin removal...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash: removeTx });
    
    console.log('🎉 Margin removed successfully!');
    console.log('📋 Transaction Hash:', removeTx);
    console.log('📦 Block Number:', receipt.blockNumber);

    // Get updated balances and position
    const freeBalanceAfter = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'freeBalance',
      args: [account.address]
    }) as bigint;

    const balanceChange = Number(freeBalanceAfter - freeBalanceBefore) / 1e6;
    
    console.log('\n💰 Results:');
    console.log(`  Free balance after: ${Number(freeBalanceAfter) / 1e6} USDC`);
    console.log(`  Balance increase: +${balanceChange.toFixed(2)} USDC`);

    // Show updated position
    const updatedPosition = await publicClient.readContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi as any,
      functionName: 'getPosition',
      args: [tokenId]
    }) as any;

    const updatedMargin = Number(updatedPosition.margin) / 1e6;
    
    console.log('\n📊 Updated Position:');
    console.log(`  New Margin: ${updatedMargin} USDC`);
    console.log(`  Size: ${Math.abs(sizeBase)} VETH (${isLong ? 'LONG' : 'SHORT'})`);
    console.log(`  Current Leverage: ${(notionalValue / updatedMargin).toFixed(2)}x`);

  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  }
}

removeMargin().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
