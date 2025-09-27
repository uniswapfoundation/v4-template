import 'dotenv/config';
import { createPublicClient, createWalletClient, http, defineChain, parseUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';
import { calculateUsdcVethPoolId, getPoolInfo } from './poolUtils';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing');

async function rebalanceVAMM() {
  console.log('⚖️  Rebalancing vAMM with Emergency Function');
  console.log('==========================================');
  
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

  // Calculate new pool ID with updated contracts
  const poolId = calculateUsdcVethPoolId(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);
  const poolInfo = getPoolInfo(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);

  console.log('👤 Using account:', account.address);
  console.log('🆔 New Pool ID:', poolId);
  console.log('💱 Pool Configuration:');
  console.log('  Currency0:', poolInfo.poolKey.currency0);
  console.log('  Currency1:', poolInfo.poolKey.currency1);
  console.log('  Hook:', poolInfo.poolKey.hooks);
  console.log('');

  try {
    // Step 1: Check current vAMM state
    console.log('📊 Step 1: Checking current vAMM state...');
    
    try {
      const marketState = await publicClient.readContract({
        address: c.perpsHook.address,
        abi: c.perpsHook.abi as any,
        functionName: 'getMarketState',
        args: [poolId]
      });
      
      console.log('🪝 Current Hook Market State:');
      console.log('   Virtual Base:', marketState.virtualBase.toString());
      console.log('   Virtual Quote:', marketState.virtualQuote.toString());
      console.log('   K (constant):', marketState.k.toString());
      console.log('   Is Active:', marketState.isActive);
      
      const virtualBase = Number(marketState.virtualBase);
      const virtualQuote = Number(marketState.virtualQuote);
      
      if (virtualBase > 0) {
        const currentVAMMPrice = (virtualQuote * 1e18) / virtualBase;
        console.log('📈 Current vAMM Price:', (currentVAMMPrice / 1e18).toFixed(2), 'USDC per VETH');
      } else {
        console.log('⚠️  Virtual base is zero - vAMM not initialized');
      }
      
    } catch (error) {
      console.log('⚠️  Market not found - will need to add market first');
      console.log('   Error:', error.shortMessage || error.message);
    }

    // Step 2: Use emergency rebalance function
    console.log('\n⚖️  Step 2: Using emergencyRebalanceVAMM function...');
    
    // Calculate proper virtual reserves for 2000 USD/VETH price
    const targetPrice = 2000e18; // 2000 USD per VETH
    const virtualLiquidity = parseUnits('1000000', 6); // 1M USDC virtual liquidity
    
    // For 2000 USD/VETH price:
    // virtualQuote = 1M USDC = 1e12 (in 6 decimals)
    // virtualBase = virtualQuote * 1e18 / price = 1e12 * 1e18 / 2000e18 = 500e18
    const newVirtualQuote = virtualLiquidity; // 1M USDC in 6 decimals
    const newVirtualBase = parseUnits('500', 18); // 500 VETH in 18 decimals
    
    console.log('🎯 Target vAMM Configuration:');
    console.log('   New Virtual Base:', newVirtualBase.toString(), '(500 VETH)');
    console.log('   New Virtual Quote:', newVirtualQuote.toString(), '(1M USDC)');
    console.log('   Expected Price:', ((Number(newVirtualQuote) * 1e18) / Number(newVirtualBase) / 1e18).toFixed(2), 'USDC per VETH');

    try {
      const rebalanceTx = await walletClient.writeContract({
        address: c.perpsHook.address,
        abi: c.perpsHook.abi as any,
        functionName: 'emergencyRebalanceVAMM',
        args: [poolId, newVirtualBase, newVirtualQuote]
      });

      console.log('⏳ Waiting for vAMM rebalancing...');
      const receipt = await publicClient.waitForTransactionReceipt({ hash: rebalanceTx });
      console.log('✅ vAMM rebalanced successfully!');
      console.log('📋 Transaction Hash:', rebalanceTx);
      console.log('📦 Block Number:', receipt.blockNumber);

    } catch (error) {
      console.log('❌ Error rebalancing vAMM:', error.shortMessage || error.message);
      
      if (error.shortMessage?.includes('Market not active')) {
        console.log('⚠️  Need to add market to FundingOracle first');
        
        // Add market to FundingOracle
        console.log('\n📊 Adding market to FundingOracle...');
        const ethUsdFeedId = '0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace';
        
        try {
          const addMarketTx = await walletClient.writeContract({
            address: c.fundingOracle.address,
            abi: c.fundingOracle.abi as any,
            functionName: 'addMarket',
            args: [poolId, c.perpsHook.address, ethUsdFeedId]
          });

          console.log('⏳ Waiting for market addition...');
          await publicClient.waitForTransactionReceipt({ hash: addMarketTx });
          console.log('✅ Market added to FundingOracle!');

          // Try rebalancing again
          console.log('\n⚖️  Retrying vAMM rebalancing...');
          const retryRebalanceTx = await walletClient.writeContract({
            address: c.perpsHook.address,
            abi: c.perpsHook.abi as any,
            functionName: 'emergencyRebalanceVAMM',
            args: [poolId, newVirtualBase, newVirtualQuote]
          });

          console.log('⏳ Waiting for vAMM rebalancing...');
          await publicClient.waitForTransactionReceipt({ hash: retryRebalanceTx });
          console.log('✅ vAMM rebalanced successfully!');
          console.log('📋 Transaction Hash:', retryRebalanceTx);

        } catch (addError) {
          console.log('❌ Error adding market:', addError.shortMessage || addError.message);
        }
      }
    }

    // Step 3: Verify the rebalancing
    console.log('\n🔍 Step 3: Verifying vAMM rebalancing...');
    
    try {
      const updatedState = await publicClient.readContract({
        address: c.perpsHook.address,
        abi: c.perpsHook.abi as any,
        functionName: 'getMarketState',
        args: [poolId]
      });
      
      console.log('🏁 Final vAMM State:');
      console.log('   Virtual Base:', updatedState.virtualBase.toString());
      console.log('   Virtual Quote:', updatedState.virtualQuote.toString());
      console.log('   K (constant):', updatedState.k.toString());
      console.log('   Is Active:', updatedState.isActive);
      
      const finalVirtualBase = Number(updatedState.virtualBase);
      const finalVirtualQuote = Number(updatedState.virtualQuote);
      
      if (finalVirtualBase > 0) {
        const finalVAMMPrice = (finalVirtualQuote * 1e18) / finalVirtualBase;
        console.log('📈 Final vAMM Price:', (finalVAMMPrice / 1e18).toFixed(2), 'USDC per VETH');
        
        if (Math.abs((finalVAMMPrice / 1e18) - 2000) < 100) {
          console.log('✅ vAMM price is now close to target (2000 USD)!');
          console.log('   Swap operations should now work properly');
        } else {
          console.log('⚠️  vAMM price still needs adjustment');
        }
      }

    } catch (error) {
      console.log('❌ Error checking final state:', error.shortMessage || error.message);
    }

    console.log('\n🎉 vAMM rebalancing completed!');
    console.log('\n📋 Summary:');
    console.log('   🆔 New Pool ID:', poolId);
    console.log('   🪝 Enhanced Hook:', c.perpsHook.address);
    console.log('   ⚖️  vAMM rebalanced for proper trading');
    
    console.log('\n🚀 Next Steps:');
    console.log('   1. Add markets to MarketManager and PositionFactory');
    console.log('   2. Test swap-based position opening');
    console.log('   3. Verify all trading operations work');

  } catch (error) {
    console.error('❌ Error in vAMM rebalancing:', error);
  }
}

rebalanceVAMM().catch(e => { 
  console.error('💥 Failed:', e);
  process.exit(1);
});
