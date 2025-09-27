import 'dotenv/config';
import { createPublicClient, createWalletClient, http, defineChain, encodeAbiParameters, keccak256 } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

// Basic network config (adjust RPC via env)
const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing');

// Pool configuration from the created pool
const POOL_ID = '0x753a8de339a2044784e515d462cd00161f933567cb21463071fd85fac2b231e0';
const CURRENCY0 = '0x748Da545386651D3d83B4AbC6267153fF2BdF91d'; // USDC (quote)
const CURRENCY1 = '0x982d92a8593c0C3c0C4F8558b8C80245d758213e'; // VETH (base)
const HOOK_ADDRESS = '0x937c62fe13D4B8e51967b6cCC55605AA965A5aC8';

// Calculate pool key for proper pool ID
const poolKey = {
  currency0: CURRENCY0,
  currency1: CURRENCY1,
  fee: 3000,
  tickSpacing: 60,
  hooks: HOOK_ADDRESS
};

function calculatePoolId(poolKey: any): `0x${string}` {
  const encoded = encodeAbiParameters(
    [
      { type: 'address', name: 'currency0' },
      { type: 'address', name: 'currency1' },
      { type: 'uint24', name: 'fee' },
      { type: 'int24', name: 'tickSpacing' },
      { type: 'address', name: 'hooks' }
    ],
    [poolKey.currency0, poolKey.currency1, poolKey.fee, poolKey.tickSpacing, poolKey.hooks]
  );
  return keccak256(encoded);
}

async function fixOwnershipAndAddMarket() {
  console.log('🔧 Fixing Ownership and Adding Market Properly');
  console.log('==============================================');
  
  const account = privateKeyToAccount(PK as `0x${string}`);
  const contracts = getContracts(CHAIN_ID);

  const transport = http(RPC_URL);
  const chain = defineChain({ 
    id: CHAIN_ID, 
    name: 'UnichainSepolia', 
    nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 }, 
    rpcUrls: { default: { http: [RPC_URL] }, public: { http: [RPC_URL] } } 
  });
  
  const publicClient = createPublicClient({ transport, chain });
  const walletClient = createWalletClient({ account, transport, chain });

  const c = contracts;

  console.log('👤 Using account:', account.address);
  console.log('💱 Pool Configuration:');
  console.log('  Currency0:', poolKey.currency0);
  console.log('  Currency1:', poolKey.currency1);
  console.log('  Fee:', poolKey.fee, 'bps');
  console.log('  Hook:', poolKey.hooks);
  
  const calculatedPoolId = calculatePoolId(poolKey);
  console.log('🆔 Calculated Pool ID:', calculatedPoolId);
  console.log('🆔 Used Pool ID:', POOL_ID);
  console.log('');

  try {
    // Step 1: Check current ownership
    console.log('🔍 Step 1: Checking current ownership...');
    
    const marketManagerOwner = await publicClient.readContract({
      address: c.marketManager.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });
    console.log('🔐 MarketManager Owner:', marketManagerOwner);
    console.log('✅ I am MarketManager owner:', marketManagerOwner.toLowerCase() === account.address.toLowerCase());

    const positionFactoryOwner = await publicClient.readContract({
      address: c.positionFactory.address,
      abi: [{'inputs':[],'name':'owner','outputs':[{'name':'','type':'address'}],'stateMutability':'view','type':'function'}],
      functionName: 'owner'
    });
    console.log('🔐 PositionFactory Owner:', positionFactoryOwner);
    console.log('✅ I am PositionFactory owner:', positionFactoryOwner.toLowerCase() === account.address.toLowerCase());

    // Step 2: Transfer PositionFactory ownership back to deployer if needed
    if (positionFactoryOwner.toLowerCase() !== account.address.toLowerCase()) {
      console.log('\n🔄 Step 2: Transferring PositionFactory ownership back to deployer...');
      
      // We need to call from the current owner (PositionManager)
      console.log('⚠️  Current owner is PositionManager, need to transfer through it');
      console.log('   This might require a different approach or the PositionManager might need a function to transfer ownership');
      
      // For now, let's check if we can still add markets through the current ownership structure
    } else {
      console.log('\n✅ Step 2: PositionFactory ownership is correct');
    }

    // Step 3: Add market to MarketManager
    console.log('\n📝 Step 3: Adding market to MarketManager...');
    
    try {
      const addMarketManagerTx = await walletClient.writeContract({
        address: c.marketManager.address,
        abi: c.marketManager.abi as any,
        functionName: 'addMarket',
        args: [calculatedPoolId, CURRENCY0, CURRENCY1, c.poolManager.address] // Using PoolManager as pool address
      });

      console.log('⏳ Waiting for MarketManager transaction...');
      await publicClient.waitForTransactionReceipt({ hash: addMarketManagerTx });
      console.log('✅ Market added to MarketManager successfully!');
      console.log('📋 Transaction Hash:', addMarketManagerTx);
    } catch (error) {
      console.log('⚠️  MarketManager Error:', error.shortMessage || error.message);
    }

    // Step 4: Add market to PositionFactory
    console.log('\n📝 Step 4: Adding market to PositionFactory...');
    
    if (positionFactoryOwner.toLowerCase() === account.address.toLowerCase()) {
      try {
        const addFactoryTx = await walletClient.writeContract({
          address: c.positionFactory.address,
          abi: c.positionFactory.abi as any,
          functionName: 'addMarket',
          args: [calculatedPoolId, CURRENCY0, CURRENCY1, c.poolManager.address]
        });

        console.log('⏳ Waiting for PositionFactory transaction...');
        await publicClient.waitForTransactionReceipt({ hash: addFactoryTx });
        console.log('✅ Market added to PositionFactory successfully!');
        console.log('📋 Transaction Hash:', addFactoryTx);
      } catch (error) {
        console.log('⚠️  PositionFactory Error:', error.shortMessage || error.message);
      }
    } else {
      console.log('❌ Not owner of PositionFactory, cannot add market directly');
      console.log('   Need to fix ownership or use alternative approach');
    }

    // Step 5: Verify market addition
    console.log('\n🔍 Step 5: Verifying market addition...');
    
    try {
      // Check MarketManager
      const marketManagerMarket = await publicClient.readContract({
        address: c.marketManager.address,
        abi: c.marketManager.abi as any,
        functionName: 'getMarket',
        args: [calculatedPoolId]
      });
      console.log('🏢 MarketManager Market:');
      console.log('   Base Asset:', marketManagerMarket.baseAsset);
      console.log('   Quote Asset:', marketManagerMarket.quoteAsset);
      console.log('   Pool Address:', marketManagerMarket.poolAddress);
      console.log('   Is Active:', marketManagerMarket.isActive);

      // Check PositionFactory
      const factoryMarket = await publicClient.readContract({
        address: c.positionFactory.address,
        abi: c.positionFactory.abi as any,
        functionName: 'getMarket',
        args: [calculatedPoolId]
      });
      console.log('🏭 PositionFactory Market:');
      console.log('   Base Asset:', factoryMarket.baseAsset);
      console.log('   Quote Asset:', factoryMarket.quoteAsset);
      console.log('   Pool Address:', factoryMarket.poolAddress);
      console.log('   Is Active:', factoryMarket.isActive);

    } catch (error) {
      console.log('⚠️  Error verifying markets:', error);
    }

    console.log('\n🎉 Market registration process completed!');

  } catch (error) {
    console.error('❌ Error in ownership fix and market addition:', error);
  }
}

fixOwnershipAndAddMarket().catch(e => { 
  console.error('💥 Failed:', e);
  process.exit(1);
});
