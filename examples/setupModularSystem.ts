import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

async function setupModularSystem() {
  console.log('🔧 Setting up Modular System Like Tests');
  
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
    // Step 1: Authorize PositionFactory in MarginAccount
    console.log('\n🔐 Step 1: Authorizing PositionFactory in MarginAccount...');
    
    const factoryAuthorized = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'authorized',
      args: [c.positionFactory.address]
    });

    if (!factoryAuthorized) {
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

    // Step 2: Transfer PositionFactory ownership to PositionManager
    console.log('\n🔄 Step 2: Transferring PositionFactory ownership to PositionManager...');
    
    const factoryOwner = await publicClient.readContract({
      address: c.positionFactory.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });

    if (factoryOwner.toLowerCase() !== c.positionManager.address.toLowerCase()) {
      const transferTx = await walletClient.writeContract({
        address: c.positionFactory.address,
        abi: c.positionFactory.abi as any,
        functionName: 'transferOwnership',
        args: [c.positionManager.address]
      });

      console.log('⏳ Waiting for ownership transfer transaction...');
      await publicClient.waitForTransactionReceipt({ hash: transferTx });
      console.log('✅ PositionFactory ownership transferred to PositionManager!');
      console.log('📋 Transaction Hash:', transferTx);
    } else {
      console.log('✅ PositionFactory already owned by PositionManager');
    }

    // Step 3: Transfer MarketManager ownership to PositionManager
    console.log('\n🔄 Step 3: Transferring MarketManager ownership to PositionManager...');
    
    const marketManagerOwner = await publicClient.readContract({
      address: c.marketManager.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });

    if (marketManagerOwner.toLowerCase() !== c.positionManager.address.toLowerCase()) {
      const transferTx = await walletClient.writeContract({
        address: c.marketManager.address,
        abi: c.marketManager.abi as any,
        functionName: 'transferOwnership',
        args: [c.positionManager.address]
      });

      console.log('⏳ Waiting for ownership transfer transaction...');
      await publicClient.waitForTransactionReceipt({ hash: transferTx });
      console.log('✅ MarketManager ownership transferred to PositionManager!');
      console.log('📋 Transaction Hash:', transferTx);
    } else {
      console.log('✅ MarketManager already owned by PositionManager');
    }

    console.log('\n🎉 Modular system setup completed successfully!');
    console.log('📝 System now matches the test configuration');

  } catch (error) {
    console.error('❌ Error in modular system setup:', error);
    throw error;
  }
}

setupModularSystem().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
