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
if (args.length < 1) {
  console.log('Usage: bun run closePositionManaged.ts <tokenId> [sizePercent]');
  console.log('Example: bun run closePositionManaged.ts 1        # Close 100% of position');
  console.log('Example: bun run closePositionManaged.ts 1 50     # Close 50% of position');
  process.exit(1);
}

const tokenId = BigInt(args[0]!);
const sizePercent = args[1] ? parseFloat(args[1]) : 100; // Default to 100% closure

async function closePosition() {
  console.log('🔚 Closing Position');
  
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
  console.log('📊 Close Percentage:', sizePercent + '%');

  try {
    // Get position details first
    const position = await publicClient.readContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi as any,
      functionName: 'getPosition',
      args: [tokenId]
    }) as any;

    console.log('\n📊 Current Position:');
    const margin = Number(position.margin) / 1e6;
    const sizeBase = Number(position.sizeBase) / 1e18;
    const entryPrice = Number(position.entryPrice) / 1e18;
    const isLong = Number(position.sizeBase) > 0;
    
    console.log(`  Margin: ${margin} USDC`);
    console.log(`  Size: ${Math.abs(sizeBase)} VETH (${isLong ? 'LONG' : 'SHORT'})`);
    console.log(`  Entry Price: ${entryPrice} USDC per VETH`);

    // Verify ownership
    if (position.owner.toLowerCase() !== account.address.toLowerCase()) {
      throw new Error('You do not own this position');
    }

    // Calculate pool ID dynamically
    const poolId = calculateUsdcVethPoolId(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);
    console.log('🆔 Using Pool ID:', poolId);

    // Get current mark price
    const markPrice = await publicClient.readContract({
      address: c.fundingOracle.address,
      abi: c.fundingOracle.abi as any,
      functionName: 'getMarkPrice',
      args: [poolId] // Our pool ID
    }) as bigint;

    const markPriceFormatted = Number(markPrice) / 1e18;
    console.log(`📊 Current Mark Price: ${markPriceFormatted} USDC per VETH`);

    // Calculate PnL before closing
    let unrealizedPnL = 0;
    if (isLong) {
      unrealizedPnL = Math.abs(sizeBase) * (markPriceFormatted - entryPrice);
    } else {
      unrealizedPnL = Math.abs(sizeBase) * (entryPrice - markPriceFormatted);
    }

    const pnlPercent = (unrealizedPnL / margin) * 100;
    const pnlColor = unrealizedPnL >= 0 ? '🟢' : '🔴';
    
    console.log('\n📈 Expected PnL:');
    console.log(`  Unrealized PnL: ${pnlColor} ${unrealizedPnL >= 0 ? '+' : ''}${unrealizedPnL.toFixed(2)} USDC`);
    console.log(`  PnL %: ${pnlColor} ${unrealizedPnL >= 0 ? '+' : ''}${pnlPercent.toFixed(2)}%`);

    // Validate close percentage
    if (sizePercent <= 0 || sizePercent > 100) {
      throw new Error('Size percentage must be between 1 and 100');
    }

    // Get current balances before closing
    const freeBalanceBefore = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'freeBalance',
      args: [account.address]
    }) as bigint;

    console.log(`\n💰 Free balance before close: ${Number(freeBalanceBefore) / 1e6} USDC`);

    // Close position
    console.log('\n🔄 Closing position...');
    
    let closeTx;
    if (sizePercent === 100) {
      // Full closure - use closePosition function
      closeTx = await walletClient.writeContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: 'closePosition',
        args: [tokenId, BigInt(Math.floor(markPriceFormatted * 1e18))] // exit price
      });
    } else {
      // Partial closure - use updatePosition function
      const newSizeBase = sizeBase * (1 - sizePercent / 100);
      const newMargin = margin * (1 - sizePercent / 100); // Proportionally reduce margin
      
      closeTx = await walletClient.writeContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: 'updatePosition',
        args: [
          tokenId, 
          BigInt(Math.floor(newSizeBase * 1e18)), // new size
          BigInt(Math.floor(newMargin * 1e6))     // new margin
        ]
      });
    }

    console.log('⏳ Waiting for position closure...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash: closeTx });
    
    console.log('🎉 Position closed successfully!');
    console.log('📋 Transaction Hash:', closeTx);
    console.log('📦 Block Number:', receipt.blockNumber);

    // Get updated balances
    const freeBalanceAfter = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'freeBalance',
      args: [account.address]
    }) as bigint;

    const balanceChange = Number(freeBalanceAfter - freeBalanceBefore) / 1e6;
    const balanceChangeColor = balanceChange >= 0 ? '🟢' : '🔴';

    console.log('\n💰 Results:');
    console.log(`  Free balance after: ${Number(freeBalanceAfter) / 1e6} USDC`);
    console.log(`  Balance change: ${balanceChangeColor} ${balanceChange >= 0 ? '+' : ''}${balanceChange.toFixed(2)} USDC`);

    if (sizePercent === 100) {
      console.log('✅ Position fully closed');
    } else {
      console.log(`✅ ${sizePercent}% of position closed`);
      
      // Show remaining position
      try {
        const remainingPosition = await publicClient.readContract({
          address: c.positionManager.address,
          abi: c.positionManager.abi as any,
          functionName: 'getPosition',
          args: [tokenId]
        }) as any;

        const remainingSize = Number(remainingPosition.sizeBase) / 1e18;
        const remainingMargin = Number(remainingPosition.margin) / 1e6;
        
        console.log('\n📊 Remaining Position:');
        console.log(`  Size: ${Math.abs(remainingSize)} VETH`);
        console.log(`  Margin: ${remainingMargin} USDC`);
      } catch (error) {
        console.log('ℹ️  Position might be fully closed');
      }
    }

  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  }
}

closePosition().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
