import 'dotenv/config';
import { createPublicClient, createWalletClient, http, defineChain, parseUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing');

async function investigateNonceIssue() {
  console.log('🔍 INVESTIGATING NONCE ISSUE THOROUGHLY');
  console.log('=======================================');
  
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

  console.log('👤 Account:', account.address);
  console.log('');

  try {
    // INVESTIGATION 1: Check nonce consistency
    console.log('🔢 INVESTIGATION 1: Nonce Consistency Check');
    console.log('===========================================');
    
    const nonce1 = await publicClient.getTransactionCount({ address: account.address });
    console.log('📊 Nonce Check 1:', nonce1);
    
    await new Promise(resolve => setTimeout(resolve, 2000)); // Wait 2 seconds
    
    const nonce2 = await publicClient.getTransactionCount({ address: account.address });
    console.log('📊 Nonce Check 2:', nonce2);
    
    if (nonce1 !== nonce2) {
      console.log('⚠️  Nonce changed during wait - transactions are still being processed');
    } else {
      console.log('✅ Nonce is stable');
    }

    // INVESTIGATION 2: Test simple token operations
    console.log('\n💰 INVESTIGATION 2: Simple Token Operation Test');
    console.log('===============================================');
    
    // Test 1: Simple USDC balance check
    try {
      const usdcBalance = await publicClient.readContract({
        address: c.mockUSDC.address,
        abi: c.mockUSDC.abi as any,
        functionName: 'balanceOf',
        args: [account.address]
      });
      console.log('✅ USDC balance check successful:', (Number(usdcBalance) / 1e6).toFixed(2), 'USDC');
    } catch (error) {
      console.log('❌ USDC balance check failed:', error.shortMessage);
    }

    // Test 2: Simple VETH balance check
    try {
      const vethBalance = await publicClient.readContract({
        address: c.mockVETH.address,
        abi: c.mockVETH.abi as any,
        functionName: 'balanceOf',
        args: [account.address]
      });
      console.log('✅ VETH balance check successful:', (Number(vethBalance) / 1e18).toFixed(6), 'VETH');
    } catch (error) {
      console.log('❌ VETH balance check failed:', error.shortMessage);
    }

    // INVESTIGATION 3: Test if the issue is specific to PoolSwapTest
    console.log('\n🏊 INVESTIGATION 3: PoolSwapTest Compatibility');
    console.log('==============================================');
    
    // Check if PoolSwapTest contract exists and is accessible
    try {
      const poolSwapTestCode = await publicClient.getBytecode({
        address: c.poolSwapTest.address
      });
      console.log('🏊 PoolSwapTest Contract:', poolSwapTestCode ? 'EXISTS' : 'NOT FOUND');
      console.log('   Address:', c.poolSwapTest.address);
      console.log('   Bytecode Length:', poolSwapTestCode ? poolSwapTestCode.length : 0);
    } catch (error) {
      console.log('❌ PoolSwapTest check failed:', error.shortMessage);
    }

    // Test 3: Try a simple approval to a different contract
    try {
      console.log('🧪 Testing USDC approval to MarginAccount (known working)...');
      const testApprovalTx = await walletClient.writeContract({
        address: c.mockUSDC.address,
        abi: c.mockUSDC.abi as any,
        functionName: 'approve',
        args: [c.marginAccount.address, parseUnits('100', 6)]
      });
      await publicClient.waitForTransactionReceipt({ hash: testApprovalTx });
      console.log('✅ USDC approval to MarginAccount successful');
    } catch (error) {
      console.log('❌ USDC approval to MarginAccount failed:', error.shortMessage);
      
      if (error.shortMessage?.includes('nonce')) {
        console.log('🔍 CONFIRMED: This is a systematic nonce issue affecting all transactions');
      } else {
        console.log('🔍 Different error - not nonce related');
      }
    }

    // INVESTIGATION 4: Check if it's related to our new contracts
    console.log('\n🔍 INVESTIGATION 4: New Contract Compatibility');
    console.log('==============================================');
    
    console.log('📋 Contract Addresses:');
    console.log('   USDC:', c.mockUSDC.address);
    console.log('   VETH:', c.mockVETH.address);
    console.log('   PerpsHook:', c.perpsHook.address);
    console.log('   PoolSwapTest:', c.poolSwapTest.address);
    
    // Check if the new token contracts have different behavior
    try {
      const usdcDecimals = await publicClient.readContract({
        address: c.mockUSDC.address,
        abi: c.mockUSDC.abi as any,
        functionName: 'decimals'
      });
      console.log('✅ USDC decimals:', usdcDecimals);
    } catch (error) {
      console.log('❌ USDC decimals check failed:', error.shortMessage);
    }

    try {
      const vethDecimals = await publicClient.readContract({
        address: c.mockVETH.address,
        abi: c.mockVETH.abi as any,
        functionName: 'decimals'
      });
      console.log('✅ VETH decimals:', vethDecimals);
    } catch (error) {
      console.log('❌ VETH decimals check failed:', error.shortMessage);
    }

    console.log('\n🎯 INVESTIGATION CONCLUSIONS:');
    console.log('============================');
    console.log('Based on the tests above, we can determine if the nonce error is:');
    console.log('A) A systematic RPC/nonce management issue (affects all transactions)');
    console.log('B) Specific to PoolSwapTest interactions');
    console.log('C) Related to our new contract deployments');
    console.log('D) Something else entirely');

  } catch (error) {
    console.error('❌ Error in nonce investigation:', error);
  }
}

investigateNonceIssue().catch(e => { 
  console.error('💥 Failed:', e);
  process.exit(1);
});
