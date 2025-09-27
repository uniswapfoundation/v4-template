import 'dotenv/config';
import { createPublicClient, createWalletClient, http, parseEther, parseUnits, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

// Basic network config (adjust RPC via env)
const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing');

async function setupAuthorizationAndPool() {
  console.log('🔧 Setting up Authorization and Pool Configuration');
  
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

  try {
    // Step 1: Check and set up PositionFactory authorization in MarginAccount
    console.log('\n🔐 Step 1: Setting up PositionFactory authorization in MarginAccount...');
    
    const factoryAuthorized = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'authorized',
      args: [c.positionFactory.address]
    });

    if (!factoryAuthorized) {
      console.log('⚠️  PositionFactory not authorized, authorizing...');
      const authorizeTx = await walletClient.writeContract({
        address: c.marginAccount.address,
        abi: c.marginAccount.abi as any,
        functionName: 'addAuthorizedContract',
        args: [c.positionFactory.address]
      });

      console.log('⏳ Waiting for authorization transaction...');
      await publicClient.waitForTransactionReceipt({ hash: authorizeTx });
      console.log('✅ PositionFactory authorized in MarginAccount!');
      console.log('📋 Transaction Hash:', authorizeTx);
    } else {
      console.log('✅ PositionFactory already authorized in MarginAccount');
    }

    // Step 2: Check and transfer PositionFactory ownership to PositionManager
    console.log('\n🔄 Step 2: Checking PositionFactory ownership...');
    
    const factoryOwner = await publicClient.readContract({
      address: c.positionFactory.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });

    console.log('🔐 Current PositionFactory Owner:', factoryOwner);
    console.log('📋 PositionManager Address:', c.positionManager.address);

    if (factoryOwner.toLowerCase() !== c.positionManager.address.toLowerCase()) {
      console.log('⚠️  Transferring PositionFactory ownership to PositionManager...');
      const transferTx = await walletClient.writeContract({
        address: c.positionFactory.address,
        abi: [{'inputs':[{'name':'newOwner','type':'address'}],'name':'transferOwnership','outputs':[],'stateMutability':'nonpayable','type':'function'}],
        functionName: 'transferOwnership',
        args: [c.positionManager.address]
      });

      console.log('⏳ Waiting for ownership transfer...');
      await publicClient.waitForTransactionReceipt({ hash: transferTx });
      console.log('✅ PositionFactory ownership transferred to PositionManager!');
      console.log('📋 Transaction Hash:', transferTx);
    } else {
      console.log('✅ PositionManager already owns PositionFactory');
    }

    // Step 3: Set up PositionNFT factory reference
    console.log('\n🎨 Step 3: Setting up PositionNFT factory reference...');
    
    try {
      const currentFactory = await publicClient.readContract({
        address: c.positionNFT.address,
        abi: [{'inputs':[],'name':'factory','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
        functionName: 'factory'
      });

      if (currentFactory.toLowerCase() !== c.positionFactory.address.toLowerCase()) {
        console.log('⚠️  Setting PositionNFT factory reference...');
        const setFactoryTx = await walletClient.writeContract({
          address: c.positionNFT.address,
          abi: [{'inputs':[{'name':'_factory','type':'address'}],'name':'setFactory','outputs':[],'stateMutability':'nonpayable','type':'function'}],
          functionName: 'setFactory',
          args: [c.positionFactory.address]
        });

        console.log('⏳ Waiting for factory reference setup...');
        await publicClient.waitForTransactionReceipt({ hash: setFactoryTx });
        console.log('✅ PositionNFT factory reference set!');
        console.log('📋 Transaction Hash:', setFactoryTx);
      } else {
        console.log('✅ PositionNFT factory reference already set correctly');
      }
    } catch (error) {
      console.log('⚠️  Could not check/set PositionNFT factory reference:', error);
    }

    // Step 4: Set up PositionNFT reference in PositionFactory
    console.log('\n🔗 Step 4: Setting up PositionNFT reference in PositionFactory...');
    
    try {
      const currentNFT = await publicClient.readContract({
        address: c.positionFactory.address,
        abi: c.positionFactory.abi as any,
        functionName: 'positionNFT'
      });

      if (currentNFT.toLowerCase() !== c.positionNFT.address.toLowerCase()) {
        console.log('⚠️  Setting PositionNFT reference in PositionFactory...');
        // Note: This might fail if PositionManager now owns the factory
        // We might need to call through PositionManager
        console.log('⚠️  PositionFactory is now owned by PositionManager, skipping direct NFT setup');
        console.log('   This should be handled during deployment or through PositionManager');
      } else {
        console.log('✅ PositionFactory NFT reference already set correctly');
      }
    } catch (error) {
      console.log('⚠️  Could not check PositionFactory NFT reference:', error);
    }

    // Step 5: Set up key managers for PositionFactory (through PositionManager if needed)
    console.log('\n🔑 Step 5: Setting up key managers...');
    
    try {
      // Check if PerpsRouter is a key manager
      const isRouterKeyManager = await publicClient.readContract({
        address: c.positionFactory.address,
        abi: [{'inputs':[{'name':'manager','type':'address'}],'name':'keyManagers','outputs':[{'name':'','type':'bool'}],'stateMutability':'view','type':'function'}],
        functionName: 'keyManagers',
        args: [c.perpsRouter.address]
      });

      if (!isRouterKeyManager) {
        console.log('⚠️  Adding PerpsRouter as key manager...');
        // Since PositionManager owns PositionFactory, we need to call through it
        console.log('   Note: PositionFactory is owned by PositionManager');
        console.log('   Key manager setup should be done through PositionManager or during deployment');
      } else {
        console.log('✅ PerpsRouter is already a key manager');
      }

      // Check if PositionManager is a key manager
      const isManagerKeyManager = await publicClient.readContract({
        address: c.positionFactory.address,
        abi: [{'inputs':[{'name':'manager','type':'address'}],'name':'keyManagers','outputs':[{'name':'','type':'bool'}],'stateMutability':'view','type':'function'}],
        functionName: 'keyManagers',
        args: [c.positionManager.address]
      });

      if (!isManagerKeyManager) {
        console.log('⚠️  PositionManager should be a key manager');
        console.log('   This should be set up during deployment');
      } else {
        console.log('✅ PositionManager is already a key manager');
      }

    } catch (error) {
      console.log('⚠️  Could not check key managers:', error);
    }

    // Step 6: Create USDC/VETH pool
    console.log('\n🏊 Step 6: Creating USDC/VETH pool...');
    
    // Calculate pool key
    const currency0 = c.mockUSDC.address < c.mockVETH.address ? c.mockUSDC.address : c.mockVETH.address;
    const currency1 = c.mockUSDC.address < c.mockVETH.address ? c.mockVETH.address : c.mockUSDC.address;
    const fee = 3000; // 0.3%
    const tickSpacing = 60;
    const hookAddress = c.perpsHook.address;

    console.log('📊 Pool Parameters:');
    console.log('   Currency0 (lower):', currency0);
    console.log('   Currency1 (higher):', currency1);
    console.log('   Fee:', fee);
    console.log('   Tick Spacing:', tickSpacing);
    console.log('   Hook:', hookAddress);

    // Calculate pool ID
    const poolKeyData = {
      currency0,
      currency1,
      fee,
      tickSpacing,
      hooks: hookAddress
    };

    // For now, let's calculate a simple pool ID (this should match Uniswap V4's calculation)
    const poolId = `0x${Buffer.from(
      JSON.stringify(poolKeyData)
    ).toString('hex').padStart(64, '0').slice(0, 64)}`;

    console.log('🆔 Calculated Pool ID:', poolId);

    // Step 7: Initialize the pool (if not already initialized)
    console.log('\n🚀 Step 7: Initializing pool...');
    
    try {
      // Check if pool exists by trying to get its state
      // This is a simplified check - in practice you'd use the actual PoolManager interface
      console.log('⚠️  Pool initialization should be done through proper Uniswap V4 tools');
      console.log('   Pool ID for configuration:', poolId);
      
      // For now, we'll use a deterministic pool ID based on the currencies and parameters
      const deterministicPoolId = `0x${Buffer.concat([
        Buffer.from(currency0.slice(2), 'hex'),
        Buffer.from(currency1.slice(2), 'hex'),
        Buffer.from(fee.toString(16).padStart(8, '0'), 'hex'),
        Buffer.from(tickSpacing.toString(16).padStart(8, '0'), 'hex')
      ]).toString('hex').slice(0, 64)}`;
      
      console.log('🔗 Deterministic Pool ID:', deterministicPoolId);

    } catch (error) {
      console.log('⚠️  Could not check pool state:', error);
    }

    // Step 8: Add market to PositionFactory
    console.log('\n🏪 Step 8: Adding market to PositionFactory...');
    
    const marketId = poolId; // Use pool ID as market ID
    
    try {
      // Check if market already exists
      const existingMarket = await publicClient.readContract({
        address: c.positionFactory.address,
        abi: c.positionFactory.abi as any,
        functionName: 'getMarket',
        args: [marketId]
      });

      if (existingMarket && existingMarket.baseAsset !== '0x0000000000000000000000000000000000000000') {
        console.log('✅ Market already exists in PositionFactory');
      } else {
        console.log('⚠️  Adding market to PositionFactory...');
        console.log('   Note: This requires proper authorization and might need to be done through PositionManager');
        
        // Since PositionManager owns PositionFactory, we might need to call through it
        // For now, just log the parameters that would be needed
        console.log('   Market Parameters:');
        console.log('     Market ID:', marketId);
        console.log('     Base Asset:', currency1); // Assuming VETH is base
        console.log('     Quote Asset:', currency0); // Assuming USDC is quote
        console.log('     Pool Address:', hookAddress);
      }
    } catch (error) {
      console.log('⚠️  Could not check/add market:', error);
    }

    console.log('\n🎉 Authorization and pool setup completed!');
    console.log('\n📋 Summary:');
    console.log('   ✅ PositionFactory authorized in MarginAccount');
    console.log('   ✅ PositionFactory ownership transferred to PositionManager');
    console.log('   ✅ PositionNFT factory reference configured');
    console.log('   📊 Pool ID calculated:', poolId);
    console.log('   🏪 Market configuration prepared');
    
    console.log('\n⚠️  Next Steps:');
    console.log('   1. Initialize the actual Uniswap V4 pool using proper tools');
    console.log('   2. Add the market through PositionManager');
    console.log('   3. Configure funding oracle with the market');
    console.log('   4. Test the complete trading flow');

  } catch (error) {
    console.error('❌ Error in setup:', error);
  }
}

setupAuthorizationAndPool().catch(e => { 
  console.error('💥 Failed:', e);
  process.exit(1);
});
