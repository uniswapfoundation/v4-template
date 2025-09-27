import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

async function addPositionManagerAsKeyManager() {
  console.log('🔑 Adding PositionManager as Key Manager in PositionFactory');
  
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
  console.log('🏭 PositionManager address:', c.positionManager.address);
  console.log('🏭 PositionFactory address:', c.positionFactory.address);

  try {
    // Check current key manager status
    const isCurrentlyKeyManager = await publicClient.readContract({
      address: c.positionFactory.address,
      abi: c.positionFactory.abi as any,
      functionName: 'keyManagers',
      args: [c.positionManager.address]
    });

    console.log('📊 PositionManager is currently key manager:', isCurrentlyKeyManager);

    if (isCurrentlyKeyManager) {
      console.log('✅ PositionManager is already a key manager!');
      return;
    }

    // Check if I'm the owner of PositionFactory
    const owner = await publicClient.readContract({
      address: c.positionFactory.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });

    console.log('🔐 PositionFactory Owner:', owner);
    console.log('✅ I am owner:', owner.toLowerCase() === account.address.toLowerCase());

    if (owner.toLowerCase() !== account.address.toLowerCase()) {
      throw new Error('Not the owner of PositionFactory - cannot add key manager');
    }

    // Add PositionManager as key manager
    console.log('🔑 Adding PositionManager as key manager...');
    
    const addKeyManagerTx = await walletClient.writeContract({
      address: c.positionFactory.address,
      abi: c.positionFactory.abi as any,
      functionName: 'addKeyManager',
      args: [c.positionManager.address]
    });

    console.log('⏳ Waiting for key manager transaction...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash: addKeyManagerTx });
    
    console.log('✅ PositionManager added as key manager successfully!');
    console.log('📋 Transaction Hash:', addKeyManagerTx);
    console.log('📦 Block Number:', receipt.blockNumber);

    // Verify key manager status
    const isNowKeyManager = await publicClient.readContract({
      address: c.positionFactory.address,
      abi: c.positionFactory.abi as any,
      functionName: 'keyManagers',
      args: [c.positionManager.address]
    });

    console.log('🎉 Final key manager status:', isNowKeyManager);

  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  }
}

addPositionManagerAsKeyManager().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
