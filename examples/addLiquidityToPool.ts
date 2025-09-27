import 'dotenv/config';
import { createPublicClient, createWalletClient, http, defineChain, parseUnits, formatUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';
import { calculateUsdcVethPoolId, getPoolInfo } from './poolUtils';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing');

// Liquidity parameters
const USDC_LIQUIDITY = '10000'; // 10,000 USDC
const VETH_LIQUIDITY = '5'; // 5 VETH (at 2000 USD/VETH = 10,000 USD)

async function addLiquidityToPool() {
  console.log('💧 Adding Liquidity to USDC/VETH Pool');
  console.log('====================================');
  
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

  // Calculate pool configuration
  const poolId = calculateUsdcVethPoolId(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);
  const poolInfo = getPoolInfo(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);

  console.log('👤 Using account:', account.address);
  console.log('🆔 Pool ID:', poolId);
  console.log('💱 Pool Configuration:');
  console.log('  Currency0 (lower):', poolInfo.poolKey.currency0);
  console.log('  Currency1 (higher):', poolInfo.poolKey.currency1);
  console.log('  Base Asset (VETH):', poolInfo.baseAsset);
  console.log('  Quote Asset (USDC):', poolInfo.quoteAsset);
  console.log('');

  try {
    // Check current balances
    console.log('💰 Step 1: Checking token balances...');
    
    const usdcBalance = await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    });
    
    const vethBalance = await publicClient.readContract({
      address: c.mockVETH.address,
      abi: c.mockVETH.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    });

    console.log('   USDC Balance:', formatUnits(usdcBalance as bigint, 6), 'USDC');
    console.log('   VETH Balance:', formatUnits(vethBalance as bigint, 18), 'VETH');

    // Calculate liquidity amounts
    const usdcAmount = parseUnits(USDC_LIQUIDITY, 6);
    const vethAmount = parseUnits(VETH_LIQUIDITY, 18);

    console.log('\n💧 Liquidity to add:');
    console.log('   USDC Amount:', USDC_LIQUIDITY, 'USDC');
    console.log('   VETH Amount:', VETH_LIQUIDITY, 'VETH');

    // Check if we have enough tokens
    if ((usdcBalance as bigint) < usdcAmount) {
      throw new Error(`Insufficient USDC. Need: ${USDC_LIQUIDITY}, Have: ${formatUnits(usdcBalance as bigint, 6)}`);
    }
    if ((vethBalance as bigint) < vethAmount) {
      throw new Error(`Insufficient VETH. Need: ${VETH_LIQUIDITY}, Have: ${formatUnits(vethBalance as bigint, 18)}`);
    }

    // Step 2: Approve tokens for PoolModifyLiquidityTest
    console.log('\n🔓 Step 2: Approving tokens for PoolModifyLiquidityTest...');
    
    // Approve USDC
    const usdcApproveTx = await walletClient.writeContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'approve',
      args: [c.poolModifyLiquidityTest.address, usdcAmount]
    });
    await publicClient.waitForTransactionReceipt({ hash: usdcApproveTx });
    console.log('✅ USDC approved');

    // Approve VETH
    const vethApproveTx = await walletClient.writeContract({
      address: c.mockVETH.address,
      abi: c.mockVETH.abi as any,
      functionName: 'approve',
      args: [c.poolModifyLiquidityTest.address, vethAmount]
    });
    await publicClient.waitForTransactionReceipt({ hash: vethApproveTx });
    console.log('✅ VETH approved');

    // Step 3: Add liquidity using PoolModifyLiquidityTest
    console.log('\n💧 Step 3: Adding liquidity to pool...');

    // Create pool key
    const poolKey = {
      currency0: poolInfo.poolKey.currency0,
      currency1: poolInfo.poolKey.currency1,
      fee: poolInfo.poolKey.fee,
      tickSpacing: poolInfo.poolKey.tickSpacing,
      hooks: poolInfo.poolKey.hooks
    };

    // Calculate tick range around current price (1:1 ratio)
    // For a 1:1 price ratio, we want ticks around 0
    const tickLower = -600; // Wider range for more liquidity
    const tickUpper = 600;

    // Calculate liquidity delta (amount of liquidity to add)
    // This is a simplified calculation - in practice you'd use more sophisticated math
    const liquidityDelta = BigInt('1000000000000000000'); // 1 unit of liquidity

    console.log('📊 Liquidity Parameters:');
    console.log('   Tick Lower:', tickLower);
    console.log('   Tick Upper:', tickUpper);
    console.log('   Liquidity Delta:', liquidityDelta.toString());

    // Add liquidity
    const modifyLiquidityTx = await walletClient.writeContract({
      address: c.poolModifyLiquidityTest.address,
      abi: c.poolModifyLiquidityTest.abi as any,
      functionName: 'modifyLiquidity',
      args: [
        poolKey,
        {
          tickLower: tickLower,
          tickUpper: tickUpper,
          liquidityDelta: liquidityDelta,
          salt: "0x0000000000000000000000000000000000000000000000000000000000000000"
        },
        "0x" // Empty hook data
      ]
    });

    console.log('⏳ Waiting for liquidity addition...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash: modifyLiquidityTx });
    console.log('✅ Liquidity added successfully!');
    console.log('📋 Transaction Hash:', modifyLiquidityTx);
    console.log('📦 Block Number:', receipt.blockNumber);
    console.log('⛽ Gas Used:', receipt.gasUsed);

    // Step 4: Verify liquidity was added
    console.log('\n🔍 Step 4: Verifying liquidity addition...');

    // Check hook state after liquidity addition
    try {
      const marketState = await publicClient.readContract({
        address: c.perpsHook.address,
        abi: c.perpsHook.abi as any,
        functionName: 'getMarketState',
        args: [poolId]
      });
      
      console.log('🪝 Updated Hook Market State:');
      console.log('   Virtual Base:', marketState.virtualBase.toString());
      console.log('   Virtual Quote:', marketState.virtualQuote.toString());
      console.log('   K (constant):', marketState.k.toString());
      console.log('   Total Long OI:', marketState.totalLongOI.toString());
      console.log('   Total Short OI:', marketState.totalShortOI.toString());
      console.log('   Is Active:', marketState.isActive);

      // Check if virtual base improved
      const virtualBase = Number(marketState.virtualBase);
      if (virtualBase > 100) {
        console.log('✅ Virtual base significantly improved - swaps should work better now');
      } else {
        console.log('⚠️  Virtual base still low - might need more liquidity');
      }

    } catch (error) {
      console.log('⚠️  Error checking hook state:', error.shortMessage || error.message);
    }

    console.log('\n🎉 Liquidity addition completed!');
    console.log('\n📋 Summary:');
    console.log('   ✅ Liquidity added to pool');
    console.log('   ✅ vAMM state should be improved');
    console.log('   ✅ Swap operations should now work better');
    
    console.log('\n🚀 Next Steps:');
    console.log('   1. Test openLongViaSwap.ts again');
    console.log('   2. Test openShortViaSwap.ts');
    console.log('   3. Monitor vAMM balance changes');

  } catch (error) {
    console.error('❌ Error adding liquidity:', error);
  }
}

addLiquidityToPool().catch(e => { 
  console.error('💥 Failed:', e);
  process.exit(1);
});
