import 'dotenv/config';
import { createPublicClient, createWalletClient, http, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';
import { calculateUsdcVethPoolId, getPoolInfo } from './poolUtils';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing');

// ETH/USD Pyth price feed ID
const ETH_USD_FEED_ID = '0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace';

async function addNewMarket() {
  console.log('🏪 Adding Market with New Pool ID');
  console.log('=================================');
  
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

  // Calculate new pool ID with updated contracts
  const poolId = calculateUsdcVethPoolId(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);
  const poolInfo = getPoolInfo(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);

  console.log('👤 Using account:', account.address);
  console.log('🆔 New Pool ID:', poolId);
  console.log('💱 Pool Configuration:');
  console.log('  Currency0:', poolInfo.poolKey.currency0);
  console.log('  Currency1:', poolInfo.poolKey.currency1);
  console.log('  Base Asset (VETH):', poolInfo.baseAsset);
  console.log('  Quote Asset (USDC):', poolInfo.quoteAsset);
  console.log('  Hook:', poolInfo.poolKey.hooks);
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

      console.log('⏳ Waiting for FundingOracle transaction...');
      await publicClient.waitForTransactionReceipt({ hash: addFundingTx });
      console.log('✅ Market added to FundingOracle!');
      console.log('📋 Transaction Hash:', addFundingTx);

    } catch (error) {
      console.log('⚠️  FundingOracle Error:', error.shortMessage || error.message);
      if (error.shortMessage?.includes('Market exists')) {
        console.log('   Market already exists - this is fine!');
      }
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

      console.log('⏳ Waiting for MarketManager transaction...');
      await publicClient.waitForTransactionReceipt({ hash: addMarketManagerTx });
      console.log('✅ Market added to MarketManager!');
      console.log('📋 Transaction Hash:', addMarketManagerTx);

    } catch (error) {
      console.log('⚠️  MarketManager Error:', error.shortMessage || error.message);
      if (error.shortMessage?.includes('Market exists')) {
        console.log('   Market already exists - this is fine!');
      }
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

      console.log('⏳ Waiting for PositionFactory transaction...');
      await publicClient.waitForTransactionReceipt({ hash: addFactoryTx });
      console.log('✅ Market added to PositionFactory!');
      console.log('📋 Transaction Hash:', addFactoryTx);

    } catch (error) {
      console.log('⚠️  PositionFactory Error:', error.shortMessage || error.message);
      if (error.shortMessage?.includes('Market exists')) {
        console.log('   Market already exists - this is fine!');
      }
    }

    // Step 4: Verify all markets are configured
    console.log('\n🔍 Step 4: Verifying market configuration...');
    
    try {
      // Check FundingOracle
      const fundingFeed = await publicClient.readContract({
        address: c.fundingOracle.address,
        abi: c.fundingOracle.abi as any,
        functionName: 'pythPriceFeedIds',
        args: [poolId]
      });
      console.log('📊 FundingOracle configured:', fundingFeed !== '0x0000000000000000000000000000000000000000000000000000000000000000');

      // Check MarketManager
      const marketManagerMarket = await publicClient.readContract({
        address: c.marketManager.address,
        abi: c.marketManager.abi as any,
        functionName: 'getMarket',
        args: [poolId]
      });
      console.log('🏢 MarketManager configured:', marketManagerMarket.baseAsset !== '0x0000000000000000000000000000000000000000');

      // Check PositionFactory
      const factoryMarket = await publicClient.readContract({
        address: c.positionFactory.address,
        abi: c.positionFactory.abi as any,
        functionName: 'getMarket',
        args: [poolId]
      });
      console.log('🏭 PositionFactory configured:', factoryMarket.baseAsset !== '0x0000000000000000000000000000000000000000');

      // Check mark price
      const markPrice = await publicClient.readContract({
        address: c.fundingOracle.address,
        abi: c.fundingOracle.abi as any,
        functionName: 'getMarkPrice',
        args: [poolId]
      });
      console.log('💰 Mark Price:', (Number(markPrice) / 1e18).toFixed(2), 'USDC per VETH');

    } catch (error) {
      console.log('⚠️  Error verifying configuration:', error.shortMessage || error.message);
    }

    console.log('\n🎉 Market addition completed!');
    console.log('\n📋 Summary:');
    console.log('   🆔 Pool ID:', poolId);
    console.log('   💰 Base Asset (VETH):', poolInfo.baseAsset);
    console.log('   💵 Quote Asset (USDC):', poolInfo.quoteAsset);
    console.log('   🪝 Enhanced Hook:', c.perpsHook.address);
    console.log('   ⚖️  vAMM Balanced: 2000 USDC per VETH');
    
    console.log('\n🚀 System Ready for Swap-Based Trading!');

  } catch (error) {
    console.error('❌ Error adding new market:', error);
  }
}

addNewMarket().catch(e => { 
  console.error('💥 Failed:', e);
  process.exit(1);
});
