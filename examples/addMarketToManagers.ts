import 'dotenv/config';
import { createPublicClient, createWalletClient, http, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

// Basic network config (adjust RPC via env)
const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing');

// Pool configuration from the created pool
const POOL_ID = '0x753a8de339a2044784e515d462cd00161f933567cb21463071fd85fac2b231e0';
const CURRENCY0 = '0x748Da545386651D3d83B4AbC6267153fF2BdF91d'; // USDC (quote)
const CURRENCY1 = '0x982d92a8593c0C3c0C4F8558b8C80245d758213e'; // VETH (base)
const HOOK_ADDRESS = '0x937c62fe13D4B8e51967b6cCC55605AA965A5aC8';

async function addMarketToManagers() {
  console.log('🏢 Adding Market to MarketManager and PositionFactory');
  console.log('====================================================');
  
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
  console.log('🆔 Pool ID:', POOL_ID);
  console.log('💰 Base Asset (VETH):', CURRENCY1);
  console.log('💵 Quote Asset (USDC):', CURRENCY0);
  console.log('🪝 Hook Address:', HOOK_ADDRESS);
  console.log('');

  try {
    // Step 1: Add market to MarketManager
    console.log('🏢 Step 1: Adding market to MarketManager...');
    
    try {
      // Check if market already exists in MarketManager
      const existingMarket = await publicClient.readContract({
        address: c.marketManager.address,
        abi: c.marketManager.abi as any,
        functionName: 'getMarket',
        args: [POOL_ID]
      });

      if (existingMarket && existingMarket.baseAsset !== '0x0000000000000000000000000000000000000000') {
        console.log('✅ Market already exists in MarketManager');
        console.log('   Base Asset:', existingMarket.baseAsset);
        console.log('   Quote Asset:', existingMarket.quoteAsset);
        console.log('   Pool Address:', existingMarket.poolAddress);
        console.log('   Is Active:', existingMarket.isActive);
      } else {
        console.log('⚠️  Adding market to MarketManager...');
        const addMarketTx = await walletClient.writeContract({
          address: c.marketManager.address,
          abi: c.marketManager.abi as any,
          functionName: 'addMarket',
          args: [POOL_ID, CURRENCY1, CURRENCY0, HOOK_ADDRESS] // marketId, baseAsset, quoteAsset, poolAddress
        });

        console.log('⏳ Waiting for MarketManager transaction...');
        await publicClient.waitForTransactionReceipt({ hash: addMarketTx });
        console.log('✅ Market added to MarketManager!');
        console.log('📋 Transaction Hash:', addMarketTx);
      }
    } catch (error) {
      console.log('⚠️  Error with MarketManager:', error);
    }

    // Step 2: Add market to PositionFactory
    console.log('\n🏭 Step 2: Adding market to PositionFactory...');
    
    try {
      // Check if market already exists in PositionFactory
      const existingFactoryMarket = await publicClient.readContract({
        address: c.positionFactory.address,
        abi: c.positionFactory.abi as any,
        functionName: 'getMarket',
        args: [POOL_ID]
      });

      if (existingFactoryMarket && existingFactoryMarket.baseAsset !== '0x0000000000000000000000000000000000000000') {
        console.log('✅ Market already exists in PositionFactory');
        console.log('   Base Asset:', existingFactoryMarket.baseAsset);
        console.log('   Quote Asset:', existingFactoryMarket.quoteAsset);
        console.log('   Pool Address:', existingFactoryMarket.poolAddress);
        console.log('   Is Active:', existingFactoryMarket.isActive);
      } else {
        console.log('⚠️  Adding market to PositionFactory...');
        
        // Since PositionManager owns PositionFactory, we need to call through PositionManager
        // Let's try calling addMarket on PositionManager which should delegate to PositionFactory
        try {
          const addFactoryMarketTx = await walletClient.writeContract({
            address: c.positionManager.address,
            abi: c.positionManager.abi as any,
            functionName: 'addMarket',
            args: [POOL_ID, CURRENCY1, CURRENCY0, HOOK_ADDRESS]
          });

          console.log('⏳ Waiting for PositionManager->PositionFactory transaction...');
          await publicClient.waitForTransactionReceipt({ hash: addFactoryMarketTx });
          console.log('✅ Market added to PositionFactory through PositionManager!');
          console.log('📋 Transaction Hash:', addFactoryMarketTx);
        } catch (managerError) {
          console.log('⚠️  Could not add through PositionManager:', managerError);
          
          // Try calling PositionFactory directly (might fail due to ownership)
          try {
            console.log('   Trying direct call to PositionFactory...');
            const directAddTx = await walletClient.writeContract({
              address: c.positionFactory.address,
              abi: c.positionFactory.abi as any,
              functionName: 'addMarket',
              args: [POOL_ID, CURRENCY1, CURRENCY0, HOOK_ADDRESS]
            });

            console.log('⏳ Waiting for direct PositionFactory transaction...');
            await publicClient.waitForTransactionReceipt({ hash: directAddTx });
            console.log('✅ Market added to PositionFactory directly!');
            console.log('📋 Transaction Hash:', directAddTx);
          } catch (directError) {
            console.log('❌ Could not add market to PositionFactory:', directError);
            console.log('   This might be due to ownership restrictions');
          }
        }
      }
    } catch (error) {
      console.log('⚠️  Error with PositionFactory:', error);
    }

    // Step 3: Verify market configuration
    console.log('\n🔍 Step 3: Verifying market configuration...');
    
    try {
      // Check MarketManager
      const marketManagerMarket = await publicClient.readContract({
        address: c.marketManager.address,
        abi: c.marketManager.abi as any,
        functionName: 'getMarket',
        args: [POOL_ID]
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
        args: [POOL_ID]
      });
      console.log('🏭 PositionFactory Market:');
      console.log('   Base Asset:', factoryMarket.baseAsset);
      console.log('   Quote Asset:', factoryMarket.quoteAsset);
      console.log('   Pool Address:', factoryMarket.poolAddress);
      console.log('   Is Active:', factoryMarket.isActive);
      console.log('   Funding Index:', factoryMarket.fundingIndex);

    } catch (error) {
      console.log('⚠️  Error verifying configuration:', error);
    }

    // Step 4: Check authorizations
    console.log('\n🔐 Step 4: Checking authorizations...');
    
    try {
      // Check if deployer is key manager for MarketManager
      const isMarketManagerKeyManager = await publicClient.readContract({
        address: c.marketManager.address,
        abi: c.marketManager.abi as any,
        functionName: 'keyManagers',
        args: [account.address]
      });
      console.log('🔑 Deployer is MarketManager key manager:', isMarketManagerKeyManager);

      // Check if deployer is key manager for PositionFactory
      const isFactoryKeyManager = await publicClient.readContract({
        address: c.positionFactory.address,
        abi: c.positionFactory.abi as any,
        functionName: 'keyManagers',
        args: [account.address]
      });
      console.log('🔑 Deployer is PositionFactory key manager:', isFactoryKeyManager);

      // Check PositionFactory ownership
      const factoryOwner = await publicClient.readContract({
        address: c.positionFactory.address,
        abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
        functionName: 'owner'
      });
      console.log('👑 PositionFactory Owner:', factoryOwner);

    } catch (error) {
      console.log('⚠️  Error checking authorizations:', error);
    }

    console.log('\n🎉 Market addition to managers completed!');
    console.log('\n📋 Summary:');
    console.log('   🆔 Pool ID:', POOL_ID);
    console.log('   💰 Base Asset (VETH):', CURRENCY1);
    console.log('   💵 Quote Asset (USDC):', CURRENCY0);
    console.log('   🪝 Hook Address:', HOOK_ADDRESS);
    
    console.log('\n⚠️  Next Steps:');
    console.log('   1. Test position opening with the new market');
    console.log('   2. Verify all contracts can interact properly');
    console.log('   3. Test the complete trading flow');

  } catch (error) {
    console.error('❌ Error adding market to managers:', error);
  }
}

addMarketToManagers().catch(e => { 
  console.error('💥 Failed:', e);
  process.exit(1);
});
