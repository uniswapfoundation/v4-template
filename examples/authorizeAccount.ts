import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

async function authorizeAccountInMarginAccount() {
  console.log('🔐 Authorizing Account in MarginAccount');
  
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
    // Check current authorization status
    const isCurrentlyAuthorized = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'authorized',
      args: [account.address]
    });

    console.log('📊 Current authorization status:', isCurrentlyAuthorized);

    if (isCurrentlyAuthorized) {
      console.log('✅ Account is already authorized in MarginAccount!');
      return;
    }

    // Check if I'm the owner of MarginAccount
    const owner = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });

    console.log('🔐 MarginAccount Owner:', owner);
    console.log('✅ I am owner:', owner.toLowerCase() === account.address.toLowerCase());

    if (owner.toLowerCase() !== account.address.toLowerCase()) {
      throw new Error('Not the owner of MarginAccount - cannot authorize');
    }

    // Authorize my account in MarginAccount
    console.log('🔐 Authorizing my account in MarginAccount...');
    
    const authorizeTx = await walletClient.writeContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'addAuthorizedContract',
      args: [account.address]
    });

    console.log('⏳ Waiting for authorization transaction...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash: authorizeTx });
    
    console.log('✅ Account authorized in MarginAccount successfully!');
    console.log('📋 Transaction Hash:', authorizeTx);
    console.log('📦 Block Number:', receipt.blockNumber);

    // Verify authorization
    const isNowAuthorized = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'authorized',
      args: [account.address]
    });

    console.log('🎉 Final authorization status:', isNowAuthorized);

  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  }
}

authorizeAccountInMarginAccount().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
