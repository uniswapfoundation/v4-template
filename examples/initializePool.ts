// Initialize the VETH-USDC pool with the PerpsHook
import 'dotenv/config';
import { http, createWalletClient, createPublicClient, parseUnits, defineChain, encodeAbiParameters, keccak256 } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

// Pool configuration
const FEE = 3000; // 0.3%
const TICK_SPACING = 60;
const INITIAL_SQRT_PRICE_X96 = "79228162514264337593543950336"; // 1:1 price

async function main() {
  console.log('🚀 Initializing VETH-USDC Pool with PerpsHook');
  
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
  console.log('🌐 Chain ID:', CHAIN_ID);

  // Order currencies by address (lower address = currency0)
  const [currency0, currency1] = c.mockUSDC.address.toLowerCase() < c.mockVETH.address.toLowerCase()
    ? [c.mockUSDC.address, c.mockVETH.address]
    : [c.mockVETH.address, c.mockUSDC.address];

  console.log('💱 Pool Configuration:');
  console.log('  Currency0:', currency0);
  console.log('  Currency1:', currency1);
  console.log('  Fee:', FEE, 'bps');
  console.log('  Tick Spacing:', TICK_SPACING);
  console.log('  Hook:', c.perpsHook.address);

  // Create pool key
  const poolKey = {
    currency0: currency0 as `0x${string}`,
    currency1: currency1 as `0x${string}`,
    fee: FEE,
    tickSpacing: TICK_SPACING,
    hooks: c.perpsHook.address
  };

  try {
    // Check if pool is already initialized
    const poolId = keccak256(
      encodeAbiParameters(
        [
          {
            type: 'tuple',
            components: [
              { name: 'currency0', type: 'address' },
              { name: 'currency1', type: 'address' },
              { name: 'fee', type: 'uint24' },
              { name: 'tickSpacing', type: 'int24' },
              { name: 'hooks', type: 'address' }
            ]
          }
        ],
        [poolKey]
      )
    );

    console.log('🆔 Pool ID:', poolId);

    // Try to get pool state to check if it's already initialized
    try {
      const poolInfo = await publicClient.readContract({
        address: c.poolManager.address,
        abi: c.poolManager.abi as any,
        functionName: 'getSlot0',
        args: [poolId]
      });
      
      console.log('✅ Pool already initialized!');
      console.log('📊 Pool info:', poolInfo);
      return;
    } catch (error: any) {
      if (error.message?.includes('PoolNotInitialized') || error.message?.includes('0x486aa307')) {
        console.log('📋 Pool not initialized yet, proceeding to initialize...');
      } else {
        console.log('ℹ️  Could not check pool state, proceeding to initialize...');
      }
    }

    // Initialize the pool
    console.log('🔄 Initializing pool...');
    const initTx = await walletClient.writeContract({
      address: c.poolManager.address,
      abi: c.poolManager.abi as any,
      functionName: 'initialize',
      args: [poolKey, BigInt(INITIAL_SQRT_PRICE_X96)]
    });

    console.log('⏳ Waiting for initialization confirmation...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash: initTx });
    
    console.log('✅ Pool initialized successfully!');
    console.log('📋 Transaction Hash:', initTx);
    console.log('📦 Block Number:', receipt.blockNumber);

    // Verify initialization
    try {
      const poolInfo = await publicClient.readContract({
        address: c.poolManager.address,
        abi: c.poolManager.abi as any,
        functionName: 'getSlot0',
        args: [poolId]
      });
      
      console.log('📊 Pool info after initialization:', poolInfo);
    } catch (error) {
      console.log('ℹ️  Could not fetch pool info after initialization');
    }

    console.log('🎉 Pool initialization complete! Ready for trading.');
    
  } catch (error) {
    console.error('❌ Error initializing pool:', error);
    throw error;
  }
}

// Execute with error handling
main().catch(e => { 
  console.error('💥 Failed to initialize pool:', e); 
  process.exit(1); 
});
