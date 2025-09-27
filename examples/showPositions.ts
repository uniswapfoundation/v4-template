import 'dotenv/config';
import { http, createPublicClient, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

async function showCurrentPositions() {
  console.log('📊 Showing Current Positions');
  
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
    // Get user positions
    const userPositions = await publicClient.readContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi as any,
      functionName: 'getUserPositions',
      args: [account.address]
    }) as bigint[];

    console.log(`\n🔍 Found ${userPositions.length} position(s)`);

    if (userPositions.length === 0) {
      console.log('📭 No positions found for this account');
      return;
    }

    // Get current mark price for calculations
    const markPrice = await publicClient.readContract({
      address: c.fundingOracle.address,
      abi: c.fundingOracle.abi as any,
      functionName: 'getMarkPrice',
      args: ['0xdb86d006b7f5ba7afb160f08da976bf53d7254e25da80f1dda0a5d36d26d656d'] // Our pool ID
    }) as bigint;

    const markPriceFormatted = Number(markPrice) / 1e18;
    console.log(`📊 Current Mark Price: ${markPriceFormatted} USDC per VETH`);

    // Process each position
    for (let i = 0; i < userPositions.length; i++) {
      const tokenId = userPositions[i];
      console.log(`\n🏷️  Position #${Number(tokenId)}`);
      console.log('═'.repeat(50));

      try {
        // Get position details
        const position = await publicClient.readContract({
          address: c.positionManager.address,
          abi: c.positionManager.abi as any,
          functionName: 'getPosition',
          args: [tokenId]
        }) as any;

        console.log('📋 Position Details:');
        console.log(`  Owner: ${position.owner}`);
        console.log(`  Margin: ${Number(position.margin) / 1e6} USDC`);
        console.log(`  Market ID: ${position.marketId}`);
        
        const sizeBase = Number(position.sizeBase) / 1e18;
        const entryPrice = Number(position.entryPrice) / 1e18;
        const isLong = Number(position.sizeBase) > 0;
        
        console.log(`  Size: ${Math.abs(sizeBase)} VETH (${isLong ? 'LONG' : 'SHORT'})`);
        console.log(`  Entry Price: ${entryPrice} USDC per VETH`);
        console.log(`  Opened At: ${new Date(Number(position.openedAt) * 1000).toLocaleString()}`);

        // Calculate current metrics
        const notionalValue = Math.abs(sizeBase) * entryPrice;
        const currentNotional = Math.abs(sizeBase) * markPriceFormatted;
        const margin = Number(position.margin) / 1e6;
        
        console.log('\n💰 Current Metrics:');
        console.log(`  Entry Notional: ${notionalValue.toFixed(2)} USDC`);
        console.log(`  Current Notional: ${currentNotional.toFixed(2)} USDC`);
        console.log(`  Leverage: ${(notionalValue / margin).toFixed(2)}x`);

        // Calculate PnL
        let unrealizedPnL = 0;
        if (isLong) {
          unrealizedPnL = Math.abs(sizeBase) * (markPriceFormatted - entryPrice);
        } else {
          unrealizedPnL = Math.abs(sizeBase) * (entryPrice - markPriceFormatted);
        }

        const pnlPercent = (unrealizedPnL / margin) * 100;
        const pnlColor = unrealizedPnL >= 0 ? '🟢' : '🔴';
        
        console.log('\n📈 Profit & Loss:');
        console.log(`  Unrealized PnL: ${pnlColor} ${unrealizedPnL >= 0 ? '+' : ''}${unrealizedPnL.toFixed(2)} USDC`);
        console.log(`  PnL %: ${pnlColor} ${unrealizedPnL >= 0 ? '+' : ''}${pnlPercent.toFixed(2)}%`);

        // Calculate liquidation price (rough estimate)
        const liquidationThreshold = margin * 0.8; // Assuming 80% maintenance margin
        let liquidationPrice = 0;
        
        if (isLong) {
          liquidationPrice = entryPrice - (liquidationThreshold / Math.abs(sizeBase));
        } else {
          liquidationPrice = entryPrice + (liquidationThreshold / Math.abs(sizeBase));
        }

        console.log('\n⚠️  Risk Metrics:');
        console.log(`  Liquidation Price: ~${liquidationPrice.toFixed(2)} USDC per VETH`);
        console.log(`  Distance to Liquidation: ${Math.abs(markPriceFormatted - liquidationPrice).toFixed(2)} USDC`);

      } catch (error) {
        console.error(`❌ Error getting details for position ${Number(tokenId)}:`, error);
      }
    }

    // Get account balance info
    console.log('\n💳 Account Balance Info:');
    console.log('═'.repeat(50));
    
    const usdcBalance = await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    }) as bigint;

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

    console.log(`💰 Wallet USDC: ${Number(usdcBalance) / 1e6} USDC`);
    console.log(`🆓 Free Margin: ${Number(freeBalance) / 1e6} USDC`);
    console.log(`🔒 Locked Margin: ${Number(lockedBalance) / 1e6} USDC`);
    console.log(`💯 Total Margin: ${Number(freeBalance + lockedBalance) / 1e6} USDC`);

  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  }
}

showCurrentPositions().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
