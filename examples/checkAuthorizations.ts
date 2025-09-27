import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

async function checkAuthorizations() {
  console.log('🔍 Checking Authorization Status');
  
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

  console.log('👤 Using account:', account.address);

  try {
    // Check PositionManager authorization for PerpsRouter
    console.log('\n🔐 PositionManager Authorization:');
    const positionManagerOwner = await publicClient.readContract({
      address: c.positionManager.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });
    console.log('  Owner:', positionManagerOwner);

    // Check if PositionManager has keyManagers feature
    try {
      const isKeyManager = await publicClient.readContract({
        address: c.positionManager.address,
        abi: [{'inputs':[{'name':'manager','type':'address'}],'name':'keyManagers','outputs':[{'name':'','type':'bool'}],'stateMutability':'view','type':'function'}],
        functionName: 'keyManagers',
        args: [c.perpsRouter.address]
      });
      console.log('  PerpsRouter is key manager:', isKeyManager);
      
      if (!isKeyManager) {
        console.log('  ❌ PerpsRouter is NOT authorized as key manager');
        
        // Try to authorize PerpsRouter
        console.log('  📝 Attempting to authorize PerpsRouter...');
        const authTx = await walletClient.writeContract({
          address: c.positionManager.address,
          abi: [{'inputs':[{'name':'manager','type':'address'},{'name':'status','type':'bool'}],'name':'setKeyManager','outputs':[],'stateMutability':'nonpayable','type':'function'}],
          functionName: 'setKeyManager',
          args: [c.perpsRouter.address, true]
        });
        
        console.log('  ⏳ Waiting for authorization transaction...');
        await publicClient.waitForTransactionReceipt({ hash: authTx });
        console.log('  ✅ PerpsRouter authorized successfully!');
        console.log('  📋 Transaction Hash:', authTx);
      } else {
        console.log('  ✅ PerpsRouter is already authorized');
      }
    } catch (error) {
      console.log('  ⚠️  keyManagers function not found, checking old authorization method');
    }

    // Check MarginAccount authorization for PerpsRouter  
    console.log('\n💰 MarginAccount Authorization:');
    try {
      const isAuthorized = await publicClient.readContract({
        address: c.marginAccount.address,
        abi: [{'inputs':[{'name':'user','type':'address'}],'name':'authorizedContracts','outputs':[{'name':'','type':'bool'}],'stateMutability':'view','type':'function'}],
        functionName: 'authorizedContracts',
        args: [c.perpsRouter.address]
      });
      console.log('  PerpsRouter is authorized:', isAuthorized);
      
      if (!isAuthorized) {
        console.log('  ❌ PerpsRouter is NOT authorized in MarginAccount');
        
        console.log('  📝 Attempting to authorize PerpsRouter in MarginAccount...');
        const marginAuthTx = await walletClient.writeContract({
          address: c.marginAccount.address,
          abi: [{'inputs':[{'name':'contractAddr','type':'address'},{'name':'status','type':'bool'}],'name':'setAuthorizedContract','outputs':[],'stateMutability':'nonpayable','type':'function'}],
          functionName: 'setAuthorizedContract',
          args: [c.perpsRouter.address, true]
        });
        
        console.log('  ⏳ Waiting for MarginAccount authorization...');
        await publicClient.waitForTransactionReceipt({ hash: marginAuthTx });
        console.log('  ✅ PerpsRouter authorized in MarginAccount successfully!');
        console.log('  📋 Transaction Hash:', marginAuthTx);
      } else {
        console.log('  ✅ PerpsRouter is already authorized in MarginAccount');
      }
    } catch (error) {
      console.log('  ⚠️  MarginAccount authorization check failed:', error);
    }

    // Check PositionFactory authorization for PerpsRouter
    console.log('\n🏭 PositionFactory Authorization:');
    try {
      const isFactoryKeyManager = await publicClient.readContract({
        address: c.positionFactory.address,
        abi: [{'inputs':[{'name':'manager','type':'address'}],'name':'keyManagers','outputs':[{'name':'','type':'bool'}],'stateMutability':'view','type':'function'}],
        functionName: 'keyManagers',
        args: [c.perpsRouter.address]
      });
      console.log('  PerpsRouter is key manager in PositionFactory:', isFactoryKeyManager);
      
      if (!isFactoryKeyManager) {
        console.log('  ❌ PerpsRouter is NOT authorized in PositionFactory');
        
        console.log('  📝 Attempting to authorize PerpsRouter in PositionFactory...');
        const factoryAuthTx = await walletClient.writeContract({
          address: c.positionFactory.address,
          abi: [{'inputs':[{'name':'manager','type':'address'},{'name':'status','type':'bool'}],'name':'setKeyManager','outputs':[],'stateMutability':'nonpayable','type':'function'}],
          functionName: 'setKeyManager',
          args: [c.perpsRouter.address, true]
        });
        
        console.log('  ⏳ Waiting for PositionFactory authorization...');
        await publicClient.waitForTransactionReceipt({ hash: factoryAuthTx });
        console.log('  ✅ PerpsRouter authorized in PositionFactory successfully!');
        console.log('  📋 Transaction Hash:', factoryAuthTx);
      } else {
        console.log('  ✅ PerpsRouter is already authorized in PositionFactory');
      }
    } catch (error) {
      console.log('  ⚠️  PositionFactory authorization check failed:', error);
    }

    console.log('\n🎉 Authorization checks completed!');

  } catch (error) {
    console.error('❌ Error checking authorizations:', error);
  }
}

checkAuthorizations().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
