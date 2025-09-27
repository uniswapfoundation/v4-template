import 'dotenv/config';
import { http, createPublicClient, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

async function quickPortfolio() {
  console.log('📊 Quick Portfolio Overview');
  
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

  try {
    // Get account balance info using the same pattern as showPositions
    const freeBalance = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'freeBalance',
      args: [account.address]
    }) as bigint;

    const lockedBalance = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'lockedBalance',
      args: [account.address]
    }) as bigint;

    console.log('\n💰 Account Balances:');
    console.log(`  Free Balance: ${Number(freeBalance) / 1e6} USDC`);
    console.log(`  Locked Balance: ${Number(lockedBalance) / 1e6} USDC`);
    console.log(`  Total Balance: ${Number(freeBalance + lockedBalance) / 1e6} USDC`);

    // Get current mark price
    const markPrice = await publicClient.readContract({
      address: c.fundingOracle.address,
      abi: c.fundingOracle.abi as any,
      functionName: 'getMarkPrice',
      args: ['0xdb86d006b7f5ba7afb160f08da976bf53d7254e25da80f1dda0a5d36d26d656d']
    }) as bigint;

    const markPriceFormatted = Number(markPrice) / 1e18;
    console.log(`📊 Current Mark Price: ${markPriceFormatted.toFixed(2)} USDC per VETH`);

    // Check known positions (we know positions 1 and 2 exist)
    const knownPositions = [1, 2]; // Add more if you know they exist
    const positions = [];

    for (const posId of knownPositions) {
      try {
        const position = await publicClient.readContract({
          address: c.positionManager.address,
          abi: c.positionManager.abi as any,
          functionName: 'getPosition',
          args: [BigInt(posId)]
        }) as any;

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
            tokenId: posId,
            margin,
            sizeBase,
            entryPrice,
            isLong,
            unrealizedPnL,
            pnlPercent,
            notionalValue,
            leverage
          });
        }
      } catch (error) {
        console.log(`Position ${posId} not found or not owned`);
      }
    }

    if (positions.length === 0) {
      console.log('\n📭 No positions found');
      return;
    }

    console.log(`\n📈 Active Positions (${positions.length}):`);
    console.log('─'.repeat(60));

    let totalPnL = 0;
    let totalNotional = 0;

    positions.forEach((pos) => {
      const pnlColor = pos.unrealizedPnL >= 0 ? '🟢' : '🔴';
      const typeIcon = pos.isLong ? '📈' : '📉';
      
      console.log(`${typeIcon} Position #${pos.tokenId} (${pos.isLong ? 'LONG' : 'SHORT'})`);
      console.log(`  Size: ${Math.abs(pos.sizeBase).toFixed(4)} VETH`);
      console.log(`  Margin: ${pos.margin.toFixed(2)} USDC`);
      console.log(`  Entry: ${pos.entryPrice.toFixed(2)} | Current: ${markPriceFormatted.toFixed(2)} USDC`);
      console.log(`  Leverage: ${pos.leverage.toFixed(2)}x`);
      console.log(`  PnL: ${pnlColor} ${pos.unrealizedPnL >= 0 ? '+' : ''}${pos.unrealizedPnL.toFixed(2)} USDC (${pos.unrealizedPnL >= 0 ? '+' : ''}${pos.pnlPercent.toFixed(2)}%)`);
      console.log('─'.repeat(40));

      totalPnL += pos.unrealizedPnL;
      totalNotional += pos.notionalValue;
    });

    // Portfolio summary
    const totalMarginUsed = positions.reduce((sum, pos) => sum + pos.margin, 0);
    const portfolioPnLColor = totalPnL >= 0 ? '🟢' : '🔴';
    
    console.log('📊 Portfolio Summary:');
    console.log(`  Total Positions: ${positions.length}`);
    console.log(`  Total Margin Used: ${totalMarginUsed.toFixed(2)} USDC`);
    console.log(`  Total PnL: ${portfolioPnLColor} ${totalPnL >= 0 ? '+' : ''}${totalPnL.toFixed(2)} USDC`);

    console.log('\n📖 Available Commands:');
    console.log('  🔍 bun run showPositions.ts <id>     - View position details');
    console.log('  💰 bun run addMargin.ts <id> <amt>   - Add margin');
    console.log('  📉 bun run removeMargin.ts <id> <amt>- Remove margin');
    console.log('  🔚 bun run closePositionManaged.ts <id> [%] - Close position');

  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  }
}

quickPortfolio().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
