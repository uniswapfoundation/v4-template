import 'dotenv/config';
import { http, createPublicClient, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

async function showAllPositions() {
  console.log('📊 All Positions Overview');
  
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
  const c = getContracts(CHAIN_ID);

  console.log('👤 Account:', account.address);
  console.log('🌐 Chain ID:', CHAIN_ID);

  try {
    // Get account balance info
    const freeBalance = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'freeBalance',
      args: [account.address]
    }) as bigint;

    const totalBalance = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'totalBalance',
      args: [account.address]
    }) as bigint;

    console.log('\n💰 Account Balances:');
    console.log(`  Free Balance: ${Number(freeBalance) / 1e6} USDC`);
    console.log(`  Total Balance: ${Number(totalBalance) / 1e6} USDC`);
    console.log(`  Margin Used: ${Number(totalBalance - freeBalance) / 1e6} USDC`);

    // Get current mark price for PnL calculations
    const markPrice = await publicClient.readContract({
      address: c.fundingOracle.address,
      abi: c.fundingOracle.abi as any,
      functionName: 'getMarkPrice',
      args: ['0xdb86d006b7f5ba7afb160f08da976bf53d7254e25da80f1dda0a5d36d26d656d']
    }) as bigint;

    const markPriceFormatted = Number(markPrice) / 1e18;
    console.log(`📊 Current Mark Price: ${markPriceFormatted.toFixed(2)} USDC per VETH`);

    // We'll check for positions by scanning position IDs
    // Since we don't have easy access to totalSupply, we'll check a reasonable range
    const maxCheckRange = 50; // Check up to 50 position IDs
    
    console.log(`🔍 Checking for positions (scanning IDs 1-${maxCheckRange})...`);

    const positions = [];
    let totalPnL = 0;
    let totalNotional = 0;

    // Check each token ID to see if we own it and if it exists
    for (let i = 1; i <= maxCheckRange; i++) {
      try {
        // Try to get position details - this will fail if position doesn't exist or we don't own it
        const position = await publicClient.readContract({
          address: c.positionManager.address,
          abi: c.positionManager.abi as any,
          functionName: 'getPosition',
          args: [BigInt(i)]
        }) as any;

        // Check if we own this position
        if (position.owner.toLowerCase() === account.address.toLowerCase()) {
          const margin = Number(position.margin) / 1e6;
          const sizeBase = Number(position.sizeBase) / 1e18;
          const entryPrice = Number(position.entryPrice) / 1e18;
          const isLong = Number(position.sizeBase) > 0;
          
          // Calculate PnL
          let unrealizedPnL = 0;
          if (isLong) {
            unrealizedPnL = Math.abs(sizeBase) * (markPriceFormatted - entryPrice);
          } else {
            unrealizedPnL = Math.abs(sizeBase) * (entryPrice - markPriceFormatted);
          }

          const pnlPercent = (unrealizedPnL / margin) * 100;
          const notionalValue = Math.abs(sizeBase) * markPriceFormatted;
          const leverage = notionalValue / margin;

          positions.push({
            tokenId: i,
            margin,
            sizeBase,
            entryPrice,
            isLong,
            unrealizedPnL,
            pnlPercent,
            notionalValue,
            leverage
          });

          totalPnL += unrealizedPnL;
          totalNotional += notionalValue;
        }
      } catch (error) {
        // Position might not exist or not owned by us, continue silently
        continue;
      }
    }

    if (positions.length === 0) {
      console.log('📭 No positions found in scanned range');
      console.log('💡 Try running showPositions.ts with a specific position ID if you have positions beyond ID 50');
      return;
    }

    console.log(`\n📈 Positions Summary (${positions.length} positions found):`);
    console.log('─'.repeat(80));

    positions.forEach((pos, index) => {
      const pnlColor = pos.unrealizedPnL >= 0 ? '🟢' : '🔴';
      const typeIcon = pos.isLong ? '📈' : '📉';
      
      console.log(`${typeIcon} Position #${pos.tokenId} (${pos.isLong ? 'LONG' : 'SHORT'})`);
      console.log(`  Size: ${Math.abs(pos.sizeBase).toFixed(4)} VETH`);
      console.log(`  Margin: ${pos.margin.toFixed(2)} USDC`);
      console.log(`  Entry Price: ${pos.entryPrice.toFixed(2)} USDC`);
      console.log(`  Leverage: ${pos.leverage.toFixed(2)}x`);
      console.log(`  Notional: ${pos.notionalValue.toFixed(2)} USDC`);
      console.log(`  PnL: ${pnlColor} ${pos.unrealizedPnL >= 0 ? '+' : ''}${pos.unrealizedPnL.toFixed(2)} USDC (${pos.unrealizedPnL >= 0 ? '+' : ''}${pos.pnlPercent.toFixed(2)}%)`);
      
      if (index < positions.length - 1) {
        console.log('─'.repeat(40));
      }
    });

    // Portfolio summary
    console.log('\n📊 Portfolio Summary:');
    console.log('─'.repeat(50));
    
    const totalMarginUsed = positions.reduce((sum, pos) => sum + pos.margin, 0);
    const avgLeverage = totalNotional / totalMarginUsed;
    const totalPnLPercent = (totalPnL / totalMarginUsed) * 100;
    const portfolioPnLColor = totalPnL >= 0 ? '🟢' : '🔴';
    
    console.log(`  Total Positions: ${positions.length}`);
    console.log(`  Total Margin Used: ${totalMarginUsed.toFixed(2)} USDC`);
    console.log(`  Total Notional: ${totalNotional.toFixed(2)} USDC`);
    console.log(`  Average Leverage: ${avgLeverage.toFixed(2)}x`);
    console.log(`  Total PnL: ${portfolioPnLColor} ${totalPnL >= 0 ? '+' : ''}${totalPnL.toFixed(2)} USDC (${totalPnL >= 0 ? '+' : ''}${totalPnLPercent.toFixed(2)}%)`);
    
    // Risk assessment
    console.log('\n⚠️  Risk Assessment:');
    const highLeveragePositions = positions.filter(p => p.leverage > 5).length;
    const negativePositions = positions.filter(p => p.unrealizedPnL < 0).length;
    
    if (highLeveragePositions > 0) {
      console.log(`  🟡 ${highLeveragePositions} position(s) with leverage > 5x`);
    }
    if (negativePositions > 0) {
      console.log(`  🔴 ${negativePositions} position(s) in the red`);
    }
    if (totalPnL < -totalMarginUsed * 0.5) {
      console.log(`  🚨 Portfolio down more than 50% - consider risk management`);
    }
    if (highLeveragePositions === 0 && negativePositions === 0) {
      console.log(`  ✅ Portfolio looks healthy`);
    }

    console.log('\n📖 Quick Commands:');
    console.log('  🔍 View specific position: bun run showPositions.ts <tokenId>');
    console.log('  💰 Add margin: bun run addMargin.ts <tokenId> <amount>');
    console.log('  📉 Remove margin: bun run removeMargin.ts <tokenId> <amount>');
    console.log('  🔚 Close position: bun run closePositionManaged.ts <tokenId> [percent]');

  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  }
}

showAllPositions().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
