import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain, encodeAbiParameters, keccak256 } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

async function addMarketToPositionManager() {
  console.log('📝 Adding Market to PositionManager');
  
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

  console.log('💱 Pool Configuration:');
  console.log('  Currency0:', currency0);
  console.log('  Currency1:', currency1);
  console.log('  Fee:', fee, 'bps');
  console.log('  Hook:', hooks);

  // Calculate poolId using the same method as Uniswap V4
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
    // Check if I'm the owner of PositionManager
    const owner = await publicClient.readContract({
      address: c.positionManager.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });

    console.log('🔐 PositionManager Owner:', owner);
    console.log('📍 My Address:', account.address);
    console.log('✅ I am owner:', owner.toLowerCase() === account.address.toLowerCase());

    if (owner.toLowerCase() !== account.address.toLowerCase()) {
      throw new Error('Not the owner of PositionManager - cannot add market');
    }

    // Determine base and quote assets correctly
    // VETH should be the base asset, USDC should be the quote asset
    const baseAsset = currency0.toLowerCase() === c.mockVETH.address.toLowerCase() ? c.mockVETH.address : c.mockUSDC.address;
    const quoteAsset = currency0.toLowerCase() === c.mockVETH.address.toLowerCase() ? c.mockUSDC.address : c.mockVETH.address;
    
    console.log('📝 Adding market to PositionManager...');
    console.log('  Market ID (Pool ID):', poolId);
    console.log('  Base Asset (VETH):', baseAsset);
    console.log('  Quote Asset (USDC):', quoteAsset);
    console.log('  Pool Address:', c.poolManager.address);

    const addMarketTx = await walletClient.writeContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi as any,
      functionName: 'addMarket',
      args: [poolId, baseAsset, quoteAsset, c.poolManager.address]
    });

    console.log('⏳ Waiting for transaction confirmation...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash: addMarketTx });
    
    console.log('✅ Market added to PositionManager successfully!');
    console.log('📋 Transaction Hash:', addMarketTx);
    console.log('📦 Block Number:', receipt.blockNumber);

    console.log('🎉 PositionManager configured successfully!');

  } catch (error) {
    console.error('❌ Error:', error);
    
    // If the error mentions "already exists" or similar, that's actually good
    if (error instanceof Error && error.message.includes('already')) {
      console.log('ℹ️  Market might already exist, which is fine');
    } else {
      throw error;
    }
  }
}

addMarketToPositionManager().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
