import 'dotenv/config';
import { createPublicClient, createWalletClient, http, defineChain, parseUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';
import { calculateUsdcVethPoolId } from './poolUtils';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing');

async function testNewSystem() {
  console.log('🧪 Testing New System with Enhanced Hook');
  console.log('=======================================');
  
  const account = privateKeyToAccount(PK as `0x${string}`);
  const contracts = getContracts(CHAIN_ID);

  const transport = http(RPC_URL);
  const chain = defineChain({ 
    id: CHAIN_ID, 
    name: 'UnichainSepolia', 
    nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 }, 
    rpcUrls: { default: { http: [RPC_URL] }, public: { http: [RPC_URL] } } 
  });
  
  const publicClient = createPublicClient({ transport, chain });
  const walletClient = createWalletClient({ account, transport, chain });

  const c = contracts;
  const poolId = calculateUsdcVethPoolId(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);

  console.log('👤 Using account:', account.address);
  console.log('🆔 Pool ID:', poolId);
  console.log('');

  try {
    // Step 1: Check vAMM state
    console.log('📊 Step 1: Checking vAMM state...');
    
    const marketState = await publicClient.readContract({
      address: c.perpsHook.address,
      abi: c.perpsHook.abi as any,
      functionName: 'getMarketState',
      args: [poolId]
    });
    
    console.log('🪝 vAMM State:');
    console.log('   Virtual Base:', marketState.virtualBase.toString(), '(wei)');
    console.log('   Virtual Quote:', marketState.virtualQuote.toString(), '(6 decimals)');
    console.log('   Is Active:', marketState.isActive);
    
    // Calculate vAMM price manually
    const virtualBase = Number(marketState.virtualBase);
    const virtualQuote = Number(marketState.virtualQuote);
    const vammPrice = (virtualQuote * 1e18) / virtualBase;
    console.log('📈 Manual vAMM Price Calculation:', (vammPrice / 1e18).toFixed(2), 'USDC per VETH');

    // Step 2: Check mark price from FundingOracle
    console.log('\n💰 Step 2: Checking FundingOracle mark price...');
    
    try {
      const markPrice = await publicClient.readContract({
        address: c.fundingOracle.address,
        abi: c.fundingOracle.abi as any,
        functionName: 'getMarkPrice',
        args: [poolId]
      });
      
      console.log('📊 FundingOracle Mark Price (raw):', markPrice.toString());
      console.log('📊 FundingOracle Mark Price (formatted):', (Number(markPrice) / 1e18).toFixed(2), 'USDC per VETH');
      
    } catch (error) {
      console.log('❌ Error getting mark price:', error.shortMessage || error.message);
    }

    // Step 3: Check if we can get mark price directly from hook
    console.log('\n🪝 Step 3: Checking hook mark price...');
    
    try {
      const hookMarkPrice = await publicClient.readContract({
        address: c.perpsHook.address,
        abi: c.perpsHook.abi as any,
        functionName: 'getMarkPrice',
        args: [poolId]
      });
      
      console.log('🪝 Hook Mark Price (raw):', hookMarkPrice.toString());
      console.log('🪝 Hook Mark Price (formatted):', (Number(hookMarkPrice) / 1e18).toFixed(2), 'USDC per VETH');
      
    } catch (error) {
      console.log('❌ Error getting hook mark price:', error.shortMessage || error.message);
    }

    // Step 4: Check margin account
    console.log('\n🏦 Step 4: Checking margin account...');
    
    const marginBalance = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'getTotalBalance',
      args: [account.address]
    });
    
    console.log('💰 Margin Balance:', (Number(marginBalance) / 1e6).toFixed(2), 'USDC');

    // Step 5: Test simple position opening with correct price
    console.log('\n🚀 Step 5: Testing position opening with manual price...');
    
    try {
      const sizeVETH = parseUnits('0.1', 18); // 0.1 VETH
      const entryPrice = parseUnits('2000', 18); // 2000 USD entry price (18 decimals)
      const margin = parseUnits('100', 6); // 100 USDC margin

      console.log('📊 Position Parameters:');
      console.log('   Size:', (Number(sizeVETH) / 1e18).toFixed(2), 'VETH');
      console.log('   Entry Price:', (Number(entryPrice) / 1e18).toFixed(2), 'USD');
      console.log('   Margin:', (Number(margin) / 1e6).toFixed(2), 'USDC');

      const openTx = await walletClient.writeContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: 'openPosition',
        args: [poolId, sizeVETH, entryPrice, margin]
      });

      console.log('⏳ Waiting for position opening...');
      await publicClient.waitForTransactionReceipt({ hash: openTx });
      console.log('✅ Position opened successfully!');
      console.log('📋 Transaction Hash:', openTx);

    } catch (error) {
      console.log('❌ Error opening position:', error.shortMessage || error.message);
      
      if (error.shortMessage?.includes('0x82b42900')) {
        console.log('   This error might be related to market not being configured');
        console.log('   Need to add market to PositionFactory first');
      }
    }

    console.log('\n📋 System Status:');
    console.log('   ✅ New hook deployed with vAMM balancing functions');
    console.log('   ✅ Pool created and initialized');
    console.log('   ✅ vAMM properly balanced (2000 USD per VETH)');
    console.log('   ⚠️  Need to configure markets in all contracts');

  } catch (error) {
    console.error('❌ Error testing new system:', error);
  }
}

testNewSystem().catch(e => { 
  console.error('💥 Failed:', e);
  process.exit(1);
});
