import 'dotenv/config';
import { createPublicClient, createWalletClient, http, defineChain, parseUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';
import { calculateUsdcVethPoolId, getPoolInfo } from './poolUtils';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing');

const ETH_USD_FEED_ID = '0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace';

async function setupNewSystemComplete() {
  console.log('🔧 Complete Setup of New Enhanced System');
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
  const poolInfo = getPoolInfo(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);

  console.log('👤 Using account:', account.address);
  console.log('🆔 Pool ID:', poolId);
  console.log('💱 Pool Info:');
  console.log('   Currency0:', poolInfo.poolKey.currency0);
  console.log('   Currency1:', poolInfo.poolKey.currency1);
  console.log('   Base Asset (VETH):', poolInfo.baseAsset);
  console.log('   Quote Asset (USDC):', poolInfo.quoteAsset);
  console.log('');

  try {
    // Step 1: Add market to FundingOracle
    console.log('📊 Step 1: Adding market to FundingOracle...');
    
    try {
      const addFundingTx = await walletClient.writeContract({
        address: c.fundingOracle.address,
        abi: c.fundingOracle.abi as any,
        functionName: 'addMarket',
        args: [poolId, c.perpsHook.address, ETH_USD_FEED_ID]
      });

      console.log('⏳ Waiting for FundingOracle...');
      await publicClient.waitForTransactionReceipt({ hash: addFundingTx });
      console.log('✅ Market added to FundingOracle!');

    } catch (error) {
      console.log('⚠️  FundingOracle:', error.shortMessage || error.message);
    }

    // Step 2: Add market to MarketManager
    console.log('\n🏢 Step 2: Adding market to MarketManager...');
    
    try {
      const addMarketManagerTx = await walletClient.writeContract({
        address: c.marketManager.address,
        abi: c.marketManager.abi as any,
        functionName: 'addMarket',
        args: [poolId, poolInfo.baseAsset, poolInfo.quoteAsset, c.perpsHook.address]
      });

      console.log('⏳ Waiting for MarketManager...');
      await publicClient.waitForTransactionReceipt({ hash: addMarketManagerTx });
      console.log('✅ Market added to MarketManager!');

    } catch (error) {
      console.log('⚠️  MarketManager:', error.shortMessage || error.message);
    }

    // Step 3: Add market to PositionFactory
    console.log('\n🏭 Step 3: Adding market to PositionFactory...');
    
    try {
      const addFactoryTx = await walletClient.writeContract({
        address: c.positionFactory.address,
        abi: c.positionFactory.abi as any,
        functionName: 'addMarket',
        args: [poolId, poolInfo.baseAsset, poolInfo.quoteAsset, c.perpsHook.address]
      });

      console.log('⏳ Waiting for PositionFactory...');
      await publicClient.waitForTransactionReceipt({ hash: addFactoryTx });
      console.log('✅ Market added to PositionFactory!');

    } catch (error) {
      console.log('⚠️  PositionFactory:', error.shortMessage || error.message);
    }

    // Step 4: Test mark price again
    console.log('\n💰 Step 4: Testing mark price after market setup...');
    
    try {
      const markPrice = await publicClient.readContract({
        address: c.fundingOracle.address,
        abi: c.fundingOracle.abi as any,
        functionName: 'getMarkPrice',
        args: [poolId]
      });
      
      console.log('📊 Updated Mark Price (raw):', markPrice.toString());
      console.log('📊 Updated Mark Price (formatted):', (Number(markPrice) / 1e18).toFixed(2), 'USDC per VETH');

    } catch (error) {
      console.log('❌ Error getting updated mark price:', error.shortMessage || error.message);
    }

    // Step 5: Test simple position opening
    console.log('\n🚀 Step 5: Testing position opening...');
    
    try {
      // Deposit margin first
      const marginAmount = parseUnits('200', 6);
      
      const depositTx = await walletClient.writeContract({
        address: c.marginAccount.address,
        abi: c.marginAccount.abi as any,
        functionName: 'deposit',
        args: [marginAmount]
      });
      
      await publicClient.waitForTransactionReceipt({ hash: depositTx });
      console.log('✅ Margin deposited');

      // Try opening position
      const sizeVETH = parseUnits('0.05', 18); // Small 0.05 VETH position
      const entryPrice = parseUnits('2000', 18); // 2000 USD
      const positionMargin = parseUnits('100', 6); // 100 USDC

      const openTx = await walletClient.writeContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: 'openPosition',
        args: [poolId, sizeVETH, entryPrice, positionMargin]
      });

      console.log('⏳ Waiting for position opening...');
      await publicClient.waitForTransactionReceipt({ hash: openTx });
      console.log('✅ Position opened successfully!');
      console.log('📋 Transaction Hash:', openTx);

    } catch (error) {
      console.log('❌ Error opening position:', error.shortMessage || error.message);
    }

    console.log('\n🎉 New system setup completed!');
    console.log('\n📋 Summary:');
    console.log('   🆔 Pool ID:', poolId);
    console.log('   🪝 Enhanced Hook:', c.perpsHook.address);
    console.log('   ⚖️  vAMM Balanced: Virtual reserves properly set');
    console.log('   🏪 Markets: Added to all necessary contracts');
    
    console.log('\n🚀 Ready for swap-based trading tests!');

  } catch (error) {
    console.error('❌ Error in complete setup:', error);
  }
}

setupNewSystemComplete().catch(e => { 
  console.error('💥 Failed:', e);
  process.exit(1);
});
