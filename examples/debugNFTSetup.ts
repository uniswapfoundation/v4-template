import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

async function debugNFTSetup() {
  console.log('🔍 Debugging NFT Setup Based on Tests');
  
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
  const c = getContracts(CHAIN_ID);

  console.log('👤 Using account:', account.address);

  try {
    // Check 1: PositionNFT factory setup
    console.log('\n🔍 Checking PositionNFT factory setup...');
    
    // Get PositionNFT address from PositionFactory
    const positionNFTAddress = await publicClient.readContract({
      address: c.positionFactory.address,
      abi: c.positionFactory.abi as any,
      functionName: 'positionNFT'
    });
    console.log('🎨 PositionNFT address from factory:', positionNFTAddress);

    // Check if PositionNFT knows about the factory
    try {
      const nftFactory = await publicClient.readContract({
        address: positionNFTAddress,
        abi: [{'inputs':[],'name':'factory','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
        functionName: 'factory'
      });
      console.log('🏭 Factory address in PositionNFT:', nftFactory);
      console.log('✅ PositionNFT factory is correctly set:', nftFactory.toLowerCase() === c.positionFactory.address.toLowerCase());
    } catch (error) {
      console.log('❌ Could not read factory from PositionNFT');
    }

    // Check 2: PositionFactory ownership
    console.log('\n🔍 Checking PositionFactory ownership...');
    
    const factoryOwner = await publicClient.readContract({
      address: c.positionFactory.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });
    console.log('🔐 PositionFactory Owner:', factoryOwner);
    console.log('📋 PositionManager Address:', c.positionManager.address);
    console.log('✅ PositionManager owns PositionFactory:', factoryOwner.toLowerCase() === c.positionManager.address.toLowerCase());

    // Check 3: MarginAccount authorization for PositionFactory
    console.log('\n🔍 Checking MarginAccount authorization for PositionFactory...');
    
    const factoryAuthorized = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'authorized',
      args: [c.positionFactory.address]
    });
    console.log('✅ PositionFactory authorized in MarginAccount:', factoryAuthorized);

    // Check 4: MarginAccount ownership  
    console.log('\n🔍 Checking MarginAccount ownership...');
    
    const marginOwner = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });
    console.log('🔐 MarginAccount Owner:', marginOwner);
    console.log('✅ I am MarginAccount owner:', marginOwner.toLowerCase() === account.address.toLowerCase());

    // Check 5: MarketManager ownership
    console.log('\n🔍 Checking MarketManager ownership...');
    
    const marketManagerOwner = await publicClient.readContract({
      address: c.marketManager.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });
    console.log('🔐 MarketManager Owner:', marketManagerOwner);
    console.log('✅ PositionManager owns MarketManager:', marketManagerOwner.toLowerCase() === c.positionManager.address.toLowerCase());

  } catch (error) {
    console.error('❌ Error in NFT setup check:', error);
  }
}

debugNFTSetup().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
