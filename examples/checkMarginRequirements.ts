import 'dotenv/config';
import { http, createPublicClient, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';
import { calculateUsdcVethPoolId, getPoolInfo } from './poolUtils';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

async function checkMarginRequirements() {
  console.log('🔍 Checking Margin Requirements');
  
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
    // Get current mark price
    const markPrice = await publicClient.readContract({
      address: c.fundingOracle.address,
      abi: c.fundingOracle.abi as any,
      functionName: 'getMarkPrice',
      args: [poolId]
    }) as bigint;

    const markPriceFormatted = Number(markPrice) / 1e18;
    console.log(`📊 Current Mark Price: ${markPriceFormatted} USDC per VETH`);

    // Try to check if there are minimum margin requirements in MarketManager
    try {
      const minimumMargin = await publicClient.readContract({
        address: c.marketManager.address,
        abi: c.marketManager.abi as any,
        functionName: 'minimumMargin',
        args: []
      }) as bigint;
      console.log(`📏 Minimum Margin: ${Number(minimumMargin) / 1e6} USDC`);
    } catch (e) {
      console.log('📏 No minimumMargin function found');
    }

    // Try to check if there are risk parameters
    try {
      const riskParams = await publicClient.readContract({
        address: c.marketManager.address,
        abi: c.marketManager.abi as any,
        functionName: 'getRiskParameters',
        args: [poolId]
      }) as any;
      console.log('🎯 Risk Parameters:', riskParams);
    } catch (e) {
      console.log('🎯 No getRiskParameters function found');
    }

    // Try to check margin requirements
    try {
      const marginRequirement = await publicClient.readContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: 'getMarginRequirement',
        args: [poolId, BigInt(75000000000000000)] // 0.075 VETH
      }) as bigint;
      console.log(`💰 Required Margin for 0.075 VETH: ${Number(marginRequirement) / 1e6} USDC`);
    } catch (e) {
      console.log('💰 No getMarginRequirement function found');
    }

    // Let's test different margin amounts to see what works
    const testAmounts = [50, 75, 100, 150, 200, 300, 500];
    const positionSize = BigInt(75000000000000000); // 0.075 VETH
    const entryPrice = BigInt(Math.floor(markPriceFormatted * 1e18));

    console.log('\n🧪 Testing Margin Requirements:');
    console.log(`Position Size: ${Number(positionSize) / 1e18} VETH`);
    console.log(`Entry Price: ${markPriceFormatted} USDC`);

    for (const marginAmount of testAmounts) {
      try {
        const marginWei = BigInt(Math.floor(marginAmount * 1e6));
        
        // Try to simulate the openPosition call
        const result = await publicClient.simulateContract({
          address: c.positionManager.address,
          abi: c.positionManager.abi as any,
          functionName: 'openPosition',
          args: [poolId, -positionSize, entryPrice, marginWei],
          account: account.address
        });
        
        console.log(`✅ ${marginAmount} USDC: Would succeed`);
        break; // Found minimum working amount
        
      } catch (error: any) {
        if (error.message && error.message.includes('0x41c092a9')) {
          console.log(`❌ ${marginAmount} USDC: InsufficientMargin`);
        } else if (error.message && error.message.includes('InsufficientMargin')) {
          console.log(`❌ ${marginAmount} USDC: InsufficientMargin`);
        } else {
          console.log(`🟡 ${marginAmount} USDC: Other error - ${error.shortMessage || error.message?.slice(0, 100)}`);
        }
      }
    }

    // Check account balances
    const freeBalance = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'freeBalance',
      args: [account.address]
    }) as bigint;

    console.log(`\n💰 Current Free Balance: ${Number(freeBalance) / 1e6} USDC`);

  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  }
}

checkMarginRequirements().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
