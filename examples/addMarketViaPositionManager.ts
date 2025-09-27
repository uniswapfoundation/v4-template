import 'dotenv/config';
import { createPublicClient, createWalletClient, http, defineChain, encodeAbiParameters, keccak256 } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

// Basic network config (adjust RPC via env)
const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing');

// Pool configuration from the created pool
const CURRENCY0 = '0x748Da545386651D3d83B4AbC6267153fF2BdF91d'; // USDC (quote)
const CURRENCY1 = '0x982d92a8593c0C3c0C4F8558b8C80245d758213e'; // VETH (base)
const HOOK_ADDRESS = '0x937c62fe13D4B8e51967b6cCC55605AA965A5aC8';

// Calculate pool key for proper pool ID
const poolKey = {
  currency0: CURRENCY0,
  currency1: CURRENCY1,
  fee: 3000,
  tickSpacing: 60,
  hooks: HOOK_ADDRESS
};

function calculatePoolId(poolKey: any): `0x${string}` {
  const encoded = encodeAbiParameters(
    [
      { type: 'address', name: 'currency0' },
      { type: 'address', name: 'currency1' },
      { type: 'uint24', name: 'fee' },
      { type: 'int24', name: 'tickSpacing' },
      { type: 'address', name: 'hooks' }
    ],
    [poolKey.currency0, poolKey.currency1, poolKey.fee, poolKey.tickSpacing, poolKey.hooks]
  );
  return keccak256(encoded);
}

async function addMarketViaPositionManager() {
  console.log('📝 Adding Market to MarketManager & PositionFactory via PositionManager');
  console.log('===================================================================');
  
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

  console.log('👤 Using account:', account.address);
  console.log('💱 Pool Configuration:');
  console.log('  Currency0:', poolKey.currency0);
  console.log('  Currency1:', poolKey.currency1);
  console.log('  Fee:', poolKey.fee, 'bps');
  console.log('  Hook:', poolKey.hooks);
  
  const poolId = calculatePoolId(poolKey);
  console.log('🆔 Pool ID:', poolId);
  console.log('');

  try {
    // Step 1: Check PositionManager ownership
    console.log('🔍 Step 1: Checking PositionManager ownership...');
    
    const positionManagerOwner = await publicClient.readContract({
      address: c.positionManager.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });
    
    console.log('🔐 PositionManager Owner:', positionManagerOwner);
    console.log('✅ I am PositionManager owner:', positionManagerOwner.toLowerCase() === account.address.toLowerCase());
    
    if (positionManagerOwner.toLowerCase() !== account.address.toLowerCase()) {
      console.log('❌ You are not the owner of PositionManager. Cannot proceed.');
      return;
    }

    // Step 2: Add market via PositionManager
    console.log('\n📝 Step 2: Adding market via PositionManager...');
    console.log('   This will add the market to BOTH MarketManager and PositionFactory');
    
    try {
      const addMarketTx = await walletClient.writeContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: 'addMarket',
        args: [poolId, CURRENCY1, CURRENCY0, c.poolManager.address] // marketId, baseAsset, quoteAsset, poolAddress
      });

      console.log('⏳ Waiting for PositionManager transaction...');
      await publicClient.waitForTransactionReceipt({ hash: addMarketTx });
      console.log('✅ Market added via PositionManager successfully!');
      console.log('📋 Transaction Hash:', addMarketTx);
      
    } catch (error) {
      console.log('⚠️  PositionManager addMarket Error:', error.shortMessage || error.message);
      
      if (error.shortMessage?.includes('Market exists')) {
        console.log('   Market already exists - this is fine!');
      }
    }

    // Step 3: Verify market addition
    console.log('\n🔍 Step 3: Verifying market addition...');
    
    try {
      // Check MarketManager
      const marketManagerMarket = await publicClient.readContract({
        address: c.marketManager.address,
        abi: c.marketManager.abi as any,
        functionName: 'getMarket',
        args: [poolId]
      });
      console.log('🏢 MarketManager Market:');
      console.log('   Base Asset:', marketManagerMarket.baseAsset);
      console.log('   Quote Asset:', marketManagerMarket.quoteAsset);
      console.log('   Pool Address:', marketManagerMarket.poolAddress);
      console.log('   Is Active:', marketManagerMarket.isActive);
      console.log('   Funding Index:', marketManagerMarket.fundingIndex);

      // Check PositionFactory
      const factoryMarket = await publicClient.readContract({
        address: c.positionFactory.address,
        abi: c.positionFactory.abi as any,
        functionName: 'getMarket',
        args: [poolId]
      });
      console.log('🏭 PositionFactory Market:');
      console.log('   Base Asset:', factoryMarket.baseAsset);
      console.log('   Quote Asset:', factoryMarket.quoteAsset);
      console.log('   Pool Address:', factoryMarket.poolAddress);
      console.log('   Is Active:', factoryMarket.isActive);
      console.log('   Funding Index:', factoryMarket.fundingIndex);

      // Check if both are properly configured
      const marketManagerConfigured = marketManagerMarket.baseAsset !== '0x0000000000000000000000000000000000000000';
      const positionFactoryConfigured = factoryMarket.baseAsset !== '0x0000000000000000000000000000000000000000';

      console.log('\n📊 Configuration Status:');
      console.log('   MarketManager configured:', marketManagerConfigured ? '✅' : '❌');
      console.log('   PositionFactory configured:', positionFactoryConfigured ? '✅' : '❌');

      if (marketManagerConfigured && positionFactoryConfigured) {
        console.log('\n🎉 SUCCESS: Market is properly configured in both contracts!');
        console.log('   The system is now ready for trading operations.');
      } else {
        console.log('\n⚠️  PARTIAL SUCCESS: Some contracts may need additional configuration.');
      }

    } catch (error) {
      console.log('⚠️  Error verifying markets:', error);
    }

    console.log('\n🎉 Market registration process completed!');
    console.log('\n📋 Summary:');
    console.log('   🆔 Pool ID:', poolId);
    console.log('   💰 Base Asset (VETH):', CURRENCY1);
    console.log('   💵 Quote Asset (USDC):', CURRENCY0);
    console.log('   🪝 Hook Address:', HOOK_ADDRESS);
    console.log('   📊 Pool Manager:', c.poolManager.address);

  } catch (error) {
    console.error('❌ Error in market addition via PositionManager:', error);
  }
}

addMarketViaPositionManager().catch(e => { 
  console.error('💥 Failed:', e);
  process.exit(1);
});
