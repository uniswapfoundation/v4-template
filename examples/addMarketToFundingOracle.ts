import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain, encodeAbiParameters, keccak256 } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

async function addMarketToFundingOracle() {
  console.log('📝 Adding Market to FundingOracle');
  
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
    // Check if I'm the owner of FundingOracle
    const owner = await publicClient.readContract({
      address: c.fundingOracle.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });

    console.log('🔐 FundingOracle Owner:', owner);
    console.log('📍 My Address:', account.address);
    console.log('✅ I am owner:', owner.toLowerCase() === account.address.toLowerCase());

    if (owner.toLowerCase() !== account.address.toLowerCase()) {
      throw new Error('Not the owner of FundingOracle - cannot add market');
    }

    // ETH/USD Pyth feed ID (from the deployment script)
    const ethUsdFeedId = "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace";
    
    console.log('📝 Adding market to FundingOracle...');
    console.log('  Pool ID:', poolId);
    console.log('  Hook Address:', c.perpsHook.address);
    console.log('  Pyth Feed ID:', ethUsdFeedId);

    const addMarketTx = await walletClient.writeContract({
      address: c.fundingOracle.address,
      abi: c.fundingOracle.abi as any,
      functionName: 'addMarket',
      args: [poolId, c.perpsHook.address, ethUsdFeedId]
    });

    console.log('⏳ Waiting for transaction confirmation...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash: addMarketTx });
    
    console.log('✅ Market added to FundingOracle successfully!');
    console.log('📋 Transaction Hash:', addMarketTx);
    console.log('📦 Block Number:', receipt.blockNumber);

    // Check if the vammHook was properly stored
    console.log('🔍 Verifying market storage...');
    try {
      const storedVammHook = await publicClient.readContract({
        address: c.fundingOracle.address,
        abi: [
          {
            "inputs": [{"name": "poolId", "type": "bytes32"}],
            "name": "vammHooks",
            "outputs": [{"name": "", "type": "address"}],
            "stateMutability": "view",
            "type": "function"
          }
        ],
        functionName: 'vammHooks',
        args: [poolId]
      });
      
      console.log('📍 Stored vammHook address:', storedVammHook);
      console.log('📍 Expected PerpsHook address:', c.perpsHook.address);
      console.log('✅ Addresses match:', storedVammHook.toLowerCase() === c.perpsHook.address.toLowerCase());
      
      if (storedVammHook === "0x0000000000000000000000000000000000000000") {
        throw new Error('vammHook not properly stored - shows zero address');
      }
      
    } catch (error) {
      console.log('❌ Error checking vammHook storage:', error);
    }

    // Test the getMarkPrice function now
    console.log('🧪 Testing getMarkPrice...');
    const markPrice = await publicClient.readContract({
      address: c.fundingOracle.address,
      abi: c.fundingOracle.abi as any,
      functionName: 'getMarkPrice',
      args: [poolId]
    });

    console.log('📊 Mark Price:', markPrice);
    console.log('🎉 FundingOracle configured successfully!');

  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  }
}

addMarketToFundingOracle().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
