import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain, encodeAbiParameters, keccak256 } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

async function addMarketDirectly() {
  console.log('📝 Adding Market to MarketManager & PositionFactory Directly');
  
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

  // Determine base and quote assets correctly
  // VETH should be the base asset, USDC should be the quote asset
  const baseAsset = currency0.toLowerCase() === c.mockVETH.address.toLowerCase() ? c.mockVETH.address : c.mockUSDC.address;
  const quoteAsset = currency0.toLowerCase() === c.mockVETH.address.toLowerCase() ? c.mockUSDC.address : c.mockVETH.address;

  try {
    // Step 1: Add to MarketManager
    console.log('📝 Step 1: Adding market to MarketManager...');
    
    const marketManagerOwner = await publicClient.readContract({
      address: c.marketManager.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });
    
    console.log('🔐 MarketManager Owner:', marketManagerOwner);
    console.log('✅ I am MarketManager owner:', marketManagerOwner.toLowerCase() === account.address.toLowerCase());

    if (marketManagerOwner.toLowerCase() === account.address.toLowerCase()) {
      const addMarketManagerTx = await walletClient.writeContract({
        address: c.marketManager.address,
        abi: c.marketManager.abi as any,
        functionName: 'addMarket',
        args: [poolId, baseAsset, quoteAsset, c.poolManager.address]
      });

      console.log('⏳ Waiting for MarketManager transaction...');
      await publicClient.waitForTransactionReceipt({ hash: addMarketManagerTx });
      console.log('✅ Market added to MarketManager successfully!');
      console.log('📋 Transaction Hash:', addMarketManagerTx);
    } else {
      console.log('❌ Not owner of MarketManager, skipping...');
    }

  } catch (error) {
    console.error('❌ MarketManager Error:', error);
    // Continue to PositionFactory even if MarketManager fails
  }

  try {
    // Step 2: Add to PositionFactory
    console.log('\n📝 Step 2: Adding market to PositionFactory...');
    
    const positionFactoryOwner = await publicClient.readContract({
      address: c.positionFactory.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });
    
    console.log('🔐 PositionFactory Owner:', positionFactoryOwner);
    console.log('✅ I am PositionFactory owner:', positionFactoryOwner.toLowerCase() === account.address.toLowerCase());

    if (positionFactoryOwner.toLowerCase() === account.address.toLowerCase()) {
      const addPositionFactoryTx = await walletClient.writeContract({
        address: c.positionFactory.address,
        abi: c.positionFactory.abi as any,
        functionName: 'addMarket',
        args: [poolId, baseAsset, quoteAsset, c.poolManager.address]
      });

      console.log('⏳ Waiting for PositionFactory transaction...');
      await publicClient.waitForTransactionReceipt({ hash: addPositionFactoryTx });
      console.log('✅ Market added to PositionFactory successfully!');
      console.log('📋 Transaction Hash:', addPositionFactoryTx);
    } else {
      console.log('❌ Not owner of PositionFactory, skipping...');
    }

  } catch (error) {
    console.error('❌ PositionFactory Error:', error);
  }

  console.log('\n🎉 Market registration process completed!');
}

addMarketDirectly().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
