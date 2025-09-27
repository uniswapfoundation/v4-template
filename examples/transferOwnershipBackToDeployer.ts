import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

async function transferOwnershipBackToDeployer() {
  console.log('🔄 Transferring Ownership Back to Deployer');
  console.log('==========================================');
  
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
  const walletClient = createWalletClient({ account, transport, chain });
  const c = getContracts(CHAIN_ID);

  console.log('👤 Using account (deployer):', account.address);
  console.log('🎯 Target: Transfer ownership from PositionManager back to deployer');
  console.log('');

  try {
    // Step 1: Check current ownership
    console.log('🔍 Step 1: Checking current ownership...');
    
    const marketManagerOwner = await publicClient.readContract({
      address: c.marketManager.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });
    console.log('🔐 MarketManager Owner:', marketManagerOwner);
    console.log('   Is deployer:', marketManagerOwner.toLowerCase() === account.address.toLowerCase());
    console.log('   Is PositionManager:', marketManagerOwner.toLowerCase() === c.positionManager.address.toLowerCase());

    const positionFactoryOwner = await publicClient.readContract({
      address: c.positionFactory.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });
    console.log('🔐 PositionFactory Owner:', positionFactoryOwner);
    console.log('   Is deployer:', positionFactoryOwner.toLowerCase() === account.address.toLowerCase());
    console.log('   Is PositionManager:', positionFactoryOwner.toLowerCase() === c.positionManager.address.toLowerCase());

    // Step 2: Check if PositionManager has a function to transfer ownership back
    console.log('\n🔍 Step 2: Checking PositionManager capabilities...');
    
    // First, let's check if PositionManager has functions to transfer ownership of its owned contracts
    // We'll need to check if PositionManager is designed to allow this
    
    console.log('📋 PositionManager Address:', c.positionManager.address);
    console.log('⚠️  We need to check if PositionManager has functions to transfer ownership of PositionFactory and MarketManager');

    // Step 3: Attempt to transfer MarketManager ownership back to deployer
    if (marketManagerOwner.toLowerCase() === c.positionManager.address.toLowerCase()) {
      console.log('\n🔄 Step 3: Attempting to transfer MarketManager ownership back to deployer...');
      
      try {
        // Try to call transferOwnership on MarketManager through PositionManager
        // This might not work if PositionManager doesn't have a passthrough function
        console.log('⚠️  Trying direct call to MarketManager (might fail if PositionManager is owner)...');
        
        // This will likely fail, but let's try
        const transferMarketManagerTx = await walletClient.writeContract({
          address: c.marketManager.address,
          abi: c.marketManager.abi as any,
          functionName: 'transferOwnership',
          args: [account.address]
        });

        console.log('⏳ Waiting for MarketManager ownership transfer...');
        await publicClient.waitForTransactionReceipt({ hash: transferMarketManagerTx });
        console.log('✅ MarketManager ownership transferred back to deployer!');
        console.log('📋 Transaction Hash:', transferMarketManagerTx);
        
      } catch (error) {
        console.log('❌ Direct MarketManager transfer failed:', error.shortMessage || error.message);
        console.log('   This is expected if PositionManager owns it and doesn\'t allow external calls');
      }
    } else if (marketManagerOwner.toLowerCase() === account.address.toLowerCase()) {
      console.log('✅ MarketManager is already owned by deployer');
    }

    // Step 4: Attempt to transfer PositionFactory ownership back to deployer
    if (positionFactoryOwner.toLowerCase() === c.positionManager.address.toLowerCase()) {
      console.log('\n🔄 Step 4: Attempting to transfer PositionFactory ownership back to deployer...');
      
      try {
        console.log('⚠️  Trying direct call to PositionFactory (might fail if PositionManager is owner)...');
        
        const transferFactoryTx = await walletClient.writeContract({
          address: c.positionFactory.address,
          abi: c.positionFactory.abi as any,
          functionName: 'transferOwnership',
          args: [account.address]
        });

        console.log('⏳ Waiting for PositionFactory ownership transfer...');
        await publicClient.waitForTransactionReceipt({ hash: transferFactoryTx });
        console.log('✅ PositionFactory ownership transferred back to deployer!');
        console.log('📋 Transaction Hash:', transferFactoryTx);
        
      } catch (error) {
        console.log('❌ Direct PositionFactory transfer failed:', error.shortMessage || error.message);
        console.log('   This is expected if PositionManager owns it and doesn\'t allow external calls');
      }
    } else if (positionFactoryOwner.toLowerCase() === account.address.toLowerCase()) {
      console.log('✅ PositionFactory is already owned by deployer');
    }

    // Step 5: Check final ownership status
    console.log('\n🔍 Step 5: Final ownership status...');
    
    const finalMarketManagerOwner = await publicClient.readContract({
      address: c.marketManager.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });
    
    const finalPositionFactoryOwner = await publicClient.readContract({
      address: c.positionFactory.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });

    console.log('📊 Final Status:');
    console.log('   MarketManager Owner:', finalMarketManagerOwner);
    console.log('   PositionFactory Owner:', finalPositionFactoryOwner);
    console.log('   Deployer Address:', account.address);
    
    const marketManagerOwnedByDeployer = finalMarketManagerOwner.toLowerCase() === account.address.toLowerCase();
    const positionFactoryOwnedByDeployer = finalPositionFactoryOwner.toLowerCase() === account.address.toLowerCase();
    
    console.log('\n✅ Results:');
    console.log('   MarketManager owned by deployer:', marketManagerOwnedByDeployer ? '✅' : '❌');
    console.log('   PositionFactory owned by deployer:', positionFactoryOwnedByDeployer ? '✅' : '❌');

    if (marketManagerOwnedByDeployer && positionFactoryOwnedByDeployer) {
      console.log('\n🎉 SUCCESS: Both contracts are now owned by the deployer!');
      console.log('   You can now add markets directly to both contracts.');
    } else {
      console.log('\n⚠️  PARTIAL SUCCESS: Some contracts still need ownership transfer.');
      console.log('   You may need to implement functions in PositionManager to transfer ownership,');
      console.log('   or redeploy with a different ownership structure.');
    }

  } catch (error) {
    console.error('❌ Error in ownership transfer:', error);
  }
}

transferOwnershipBackToDeployer().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
