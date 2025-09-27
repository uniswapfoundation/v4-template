import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain, encodeAbiParameters, keccak256 } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

async function debugAuthorization() {
  console.log('🔍 Debugging Authorization Issues');
  
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

  // Build poolKey struct for VETH-USDC pair
  const fee = 3000; // 0.3%
  const tickSpacing = 60;
  const hooks = c.perpsHook.address;
  
  // Order currencies by address (lower address = currency0)
  const [currency0, currency1] = c.mockUSDC.address.toLowerCase() < c.mockVETH.address.toLowerCase()
    ? [c.mockUSDC.address, c.mockVETH.address]
    : [c.mockVETH.address, c.mockUSDC.address];

  // Calculate poolId
  const poolKeyEncoded = encodeAbiParameters(
    [
      { type: 'address', name: 'currency0' },
      { type: 'address', name: 'currency1' },
      { type: 'uint24', name: 'fee' },
      { type: 'int24', name: 'tickSpacing' },
      { type: 'address', name: 'hooks' }
    ],
    [currency0, currency1, fee, tickSpacing, hooks]
  );
  const poolId = keccak256(poolKeyEncoded);
  
  console.log('🆔 Pool ID:', poolId);

  try {
    // Check 1: MarginAccount authorization
    console.log('\n🔍 Checking MarginAccount authorizations...');
    
    try {
      const isAuthorized = await publicClient.readContract({
        address: c.marginAccount.address,
        abi: c.marginAccount.abi as any,
        functionName: 'authorized',
        args: [account.address]
      });
      console.log('✅ My account authorized in MarginAccount:', isAuthorized);
    } catch (error) {
      console.log('❌ Error checking MarginAccount authorization:', error.message);
    }

    try {
      const perpsHookAuthorized = await publicClient.readContract({
        address: c.marginAccount.address,
        abi: c.marginAccount.abi as any,
        functionName: 'authorized',
        args: [c.perpsHook.address]
      });
      console.log('✅ PerpsHook authorized in MarginAccount:', perpsHookAuthorized);
    } catch (error) {
      console.log('❌ Error checking PerpsHook authorization:', error.message);
    }

    try {
      const positionManagerAuthorized = await publicClient.readContract({
        address: c.marginAccount.address,
        abi: c.marginAccount.abi as any,
        functionName: 'authorized',
        args: [c.positionManager.address]
      });
      console.log('✅ PositionManager authorized in MarginAccount:', positionManagerAuthorized);
    } catch (error) {
      console.log('❌ Error checking PositionManager authorization:', error.message);
    }

    // Check 2: PositionFactory key managers
    console.log('\n🔍 Checking PositionFactory authorizations...');
    
    try {
      const isKeyManager = await publicClient.readContract({
        address: c.positionFactory.address,
        abi: c.positionFactory.abi as any,
        functionName: 'keyManagers',
        args: [account.address]
      });
      console.log('✅ My account is PositionFactory key manager:', isKeyManager);
    } catch (error) {
      console.log('❌ Error checking PositionFactory key manager:', error.message);
    }

    try {
      const positionManagerIsKeyManager = await publicClient.readContract({
        address: c.positionFactory.address,
        abi: c.positionFactory.abi as any,
        functionName: 'keyManagers',
        args: [c.positionManager.address]
      });
      console.log('✅ PositionManager is PositionFactory key manager:', positionManagerIsKeyManager);
    } catch (error) {
      console.log('❌ Error checking PositionManager as key manager:', error.message);
    }

    // Check 3: PositionFactory owner
    try {
      const factoryOwner = await publicClient.readContract({
        address: c.positionFactory.address,
        abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
        functionName: 'owner'
      });
      console.log('🔐 PositionFactory Owner:', factoryOwner);
      console.log('✅ I am PositionFactory owner:', factoryOwner.toLowerCase() === account.address.toLowerCase());
    } catch (error) {
      console.log('❌ Error checking PositionFactory owner:', error.message);
    }

    // Check 4: Market status
    console.log('\n🔍 Checking market registration...');
    
    try {
      const market = await publicClient.readContract({
        address: c.positionFactory.address,
        abi: c.positionFactory.abi as any,
        functionName: 'getMarket',
        args: [poolId]
      });
      console.log('🏪 Market in PositionFactory:', market);
    } catch (error) {
      console.log('❌ Error getting market from PositionFactory:', error.message);
    }

    // Check 5: PositionNFT setup
    console.log('\n🔍 Checking PositionNFT setup...');
    
    try {
      const positionNFTAddress = await publicClient.readContract({
        address: c.positionFactory.address,
        abi: c.positionFactory.abi as any,
        functionName: 'positionNFT'
      });
      console.log('🎨 PositionNFT address in factory:', positionNFTAddress);
    } catch (error) {
      console.log('❌ Error checking PositionNFT address:', error.message);
    }

  } catch (error) {
    console.error('❌ Error in authorization check:', error);
  }
}

debugAuthorization().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
