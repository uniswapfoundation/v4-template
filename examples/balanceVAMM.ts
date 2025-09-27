import 'dotenv/config';
import { createPublicClient, createWalletClient, http, defineChain, parseUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';
import { calculateUsdcVethPoolId, getPoolInfo } from './poolUtils';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing');

async function balanceVAMM() {
  console.log('⚖️  Balancing vAMM through Strategic Trading');
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
  const poolId = calculateUsdcVethPoolId(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);

  console.log('👤 Using account:', account.address);
  console.log('🆔 Pool ID:', poolId);

  try {
    // Step 1: Check current vAMM state
    console.log('\n📊 Step 1: Current vAMM State...');
    
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
    console.log('   Total Long OI:', marketState.totalLongOI.toString());
    console.log('   Total Short OI:', marketState.totalShortOI.toString());
    
    const virtualBase = Number(marketState.virtualBase);
    const virtualQuote = Number(marketState.virtualQuote);
    const currentVAMMPrice = (virtualQuote * 1e18) / virtualBase;
    
    console.log('📈 Current vAMM Price:', (currentVAMMPrice / 1e18).toFixed(2), 'USDC per VETH');
    console.log('🎯 Target Price: 2000 USDC per VETH');

    // Step 2: Strategy - Open short positions to increase virtualBase
    console.log('\n📉 Step 2: Opening SHORT positions to balance vAMM...');
    console.log('   Strategy: SHORT positions add to virtualBase, reducing the price');
    console.log('   This will help balance the vAMM reserves');

    // Calculate how much short OI we need to balance the vAMM
    const targetPrice = 2000e18; // 2000 USD per VETH
    const targetVirtualBase = (virtualQuote * 1e18) / targetPrice;
    const neededVirtualBase = targetVirtualBase - virtualBase;
    
    console.log('📊 Balance Calculation:');
    console.log('   Current Virtual Base:', virtualBase);
    console.log('   Target Virtual Base:', targetVirtualBase.toFixed(0));
    console.log('   Needed Additional Base:', neededVirtualBase.toFixed(0));

    if (neededVirtualBase > 0) {
      // Open several small short positions to gradually increase virtualBase
      const numPositions = 3;
      const positionSize = Math.floor(neededVirtualBase / numPositions / 1e18 * 0.8); // 80% of needed, split across positions
      
      console.log('\n🔄 Opening', numPositions, 'SHORT positions of', positionSize, 'VETH each...');
      
      for (let i = 0; i < numPositions; i++) {
        try {
          console.log(`\n📉 Opening SHORT position ${i + 1}/${numPositions}...`);
          
          const sizeWei = parseUnits(positionSize.toString(), 18);
          const marginUSDC = parseUnits('200', 6); // 200 USDC margin per position
          const entryPrice = parseUnits('2000', 18); // 2000 USD entry price

          const openTx = await walletClient.writeContract({
            address: c.positionManager.address,
            abi: c.positionManager.abi as any,
            functionName: 'openPosition',
            args: [poolId, -sizeWei, entryPrice, marginUSDC] // Negative size for SHORT
          });

          console.log('⏳ Waiting for position opening...');
          await publicClient.waitForTransactionReceipt({ hash: openTx });
          console.log('✅ SHORT position opened!');
          console.log('📋 Transaction Hash:', openTx);

          // Check updated vAMM state
          const updatedState = await publicClient.readContract({
            address: c.perpsHook.address,
            abi: c.perpsHook.abi as any,
            functionName: 'getMarketState',
            args: [poolId]
          });

          const newVirtualBase = Number(updatedState.virtualBase);
          const newVirtualQuote = Number(updatedState.virtualQuote);
          const newVAMMPrice = (newVirtualQuote * 1e18) / newVirtualBase;
          
          console.log('📊 Updated vAMM State:');
          console.log('   Virtual Base:', newVirtualBase);
          console.log('   Virtual Quote:', newVirtualQuote);
          console.log('   vAMM Price:', (newVAMMPrice / 1e18).toFixed(2), 'USDC per VETH');

        } catch (error) {
          console.log(`❌ Error opening SHORT position ${i + 1}:`, error.shortMessage || error.message);
        }
      }
    } else {
      console.log('✅ vAMM is already balanced or needs different strategy');
    }

    // Step 3: Final state check
    console.log('\n🔍 Step 3: Final vAMM State...');
    
    const finalState = await publicClient.readContract({
      address: c.perpsHook.address,
      abi: c.perpsHook.abi as any,
      functionName: 'getMarketState',
      args: [poolId]
    });
    
    const finalVirtualBase = Number(finalState.virtualBase);
    const finalVirtualQuote = Number(finalState.virtualQuote);
    const finalVAMMPrice = (finalVirtualQuote * 1e18) / finalVirtualBase;
    
    console.log('🏁 Final vAMM State:');
    console.log('   Virtual Base:', finalVirtualBase);
    console.log('   Virtual Quote:', finalVirtualQuote);
    console.log('   vAMM Price:', (finalVAMMPrice / 1e18).toFixed(2), 'USDC per VETH');
    console.log('   Total Long OI:', finalState.totalLongOI.toString());
    console.log('   Total Short OI:', finalState.totalShortOI.toString());

    // Check if balance improved
    if (finalVirtualBase > virtualBase * 2) {
      console.log('✅ vAMM balance significantly improved!');
      console.log('   Swap operations should now work better');
    } else {
      console.log('⚠️  vAMM balance needs more improvement');
      console.log('   Consider opening more SHORT positions or adjusting strategy');
    }

    console.log('\n🎉 vAMM balancing completed!');
    console.log('\n🚀 Next Steps:');
    console.log('   1. Test openShortViaSwap.ts again');
    console.log('   2. Monitor vAMM price stability');
    console.log('   3. Continue with normal trading operations');

  } catch (error) {
    console.error('❌ Error balancing vAMM:', error);
  }
}

balanceVAMM().catch(e => { 
  console.error('💥 Failed:', e);
  process.exit(1);
});
