import { createPublicClient, createWalletClient, http, parseUnits, formatUnits, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

// Define Unichain Sepolia
const unichainSepolia = defineChain({
  id: UNICHAIN_SEPOLIA,
  name: 'Unichain Sepolia',
  network: 'unichain-sepolia',
  nativeCurrency: {
    decimals: 18,
    name: 'Ethereum',
    symbol: 'ETH',
  },
  rpcUrls: {
    default: { http: ['https://sepolia.unichain.org'] },
    public: { http: ['https://sepolia.unichain.org'] },
  },
});

const transport = http('https://sepolia.unichain.org');
const account = privateKeyToAccount('0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80');

async function testMarginWithdrawal() {
  console.log('🔍 Testing Free Margin Withdrawal Functionality\n');
  
  const publicClient = createPublicClient({ chain: unichainSepolia, transport });
  const walletClient = createWalletClient({ account, chain: unichainSepolia, transport });
  const contracts = getContracts(UNICHAIN_SEPOLIA);
  
  console.log('👤 Testing Account:', account.address);
  console.log('💰 MarginAccount Address:', contracts.marginAccount.address);
  
  try {
    // Step 1: Check current balances
    console.log('\n📊 Current Balance Analysis:');
    
    const freeBalance = await publicClient.readContract({
      address: contracts.marginAccount.address,
      abi: contracts.marginAccount.abi,
      functionName: 'freeBalance',
      args: [account.address]
    }) as bigint;
    
    const lockedBalance = await publicClient.readContract({
      address: contracts.marginAccount.address,
      abi: contracts.marginAccount.abi,
      functionName: 'lockedBalance',
      args: [account.address]
    }) as bigint;
    
    const totalBalance = await publicClient.readContract({
      address: contracts.marginAccount.address,
      abi: contracts.marginAccount.abi,
      functionName: 'getTotalBalance',
      args: [account.address]
    }) as bigint;
    
    const walletUSDC = await publicClient.readContract({
      address: contracts.mockUSDC.address,
      abi: contracts.mockUSDC.abi,
      functionName: 'balanceOf',
      args: [account.address]
    }) as bigint;
    
    console.log('  💰 Free Balance (withdrawable):', formatUnits(freeBalance, 6), 'USDC');
    console.log('  🔒 Locked Balance (in positions):', formatUnits(lockedBalance, 6), 'USDC');
    console.log('  📊 Total Balance (in MarginAccount):', formatUnits(totalBalance, 6), 'USDC');
    console.log('  💳 Wallet USDC Balance:', formatUnits(walletUSDC, 6), 'USDC');
    
    // Step 2: Test withdrawal scenarios
    console.log('\n🧪 Testing Withdrawal Scenarios:');
    
    if (freeBalance === 0n) {
      console.log('❌ No free balance available for withdrawal');
      return;
    }
    
    // Test Case 1: Small withdrawal (100 USDC)
    const smallWithdrawal = parseUnits('100', 6);
    console.log('\n🔬 Test Case 1: Small Withdrawal (100 USDC)');
    
    if (freeBalance >= smallWithdrawal) {
      console.log('✅ Sufficient free balance for 100 USDC withdrawal');
      
      try {
        console.log('🔄 Attempting 100 USDC withdrawal...');
        const withdrawTx = await walletClient.writeContract({
          address: contracts.marginAccount.address,
          abi: contracts.marginAccount.abi,
          functionName: 'withdraw',
          args: [smallWithdrawal]
        });
        
        const receipt = await publicClient.waitForTransactionReceipt({ hash: withdrawTx });
        console.log('✅ Withdrawal successful!');
        console.log('📋 Transaction Hash:', withdrawTx);
        console.log('📦 Block Number:', receipt.blockNumber);
        
        // Check updated balances
        const newFreeBalance = await publicClient.readContract({
          address: contracts.marginAccount.address,
          abi: contracts.marginAccount.abi,
          functionName: 'freeBalance',
          args: [account.address]
        }) as bigint;
        
        const newWalletUSDC = await publicClient.readContract({
          address: contracts.mockUSDC.address,
          abi: contracts.mockUSDC.abi,
          functionName: 'balanceOf',
          args: [account.address]
        }) as bigint;
        
        console.log('📊 Updated Balances:');
        console.log('  💰 New Free Balance:', formatUnits(newFreeBalance, 6), 'USDC');
        console.log('  💳 New Wallet Balance:', formatUnits(newWalletUSDC, 6), 'USDC');
        console.log('  🔄 Change in Free Balance:', formatUnits(freeBalance - newFreeBalance, 6), 'USDC');
        console.log('  🔄 Change in Wallet Balance:', formatUnits(newWalletUSDC - walletUSDC, 6), 'USDC');
        
      } catch (error) {
        console.log('❌ Small withdrawal failed:', error);
      }
    } else {
      console.log('⚠️  Insufficient free balance for 100 USDC withdrawal');
      console.log('   Available:', formatUnits(freeBalance, 6), 'USDC');
    }
    
    // Test Case 2: Large withdrawal (1000 USDC)
    console.log('\n🔬 Test Case 2: Large Withdrawal (1000 USDC)');
    const largeWithdrawal = parseUnits('1000', 6);
    
    // Get current free balance again (in case it changed from previous test)
    const currentFreeBalance = await publicClient.readContract({
      address: contracts.marginAccount.address,
      abi: contracts.marginAccount.abi,
      functionName: 'freeBalance',
      args: [account.address]
    }) as bigint;
    
    if (currentFreeBalance >= largeWithdrawal) {
      console.log('✅ Sufficient free balance for 1000 USDC withdrawal');
      
      try {
        console.log('🔄 Attempting 1000 USDC withdrawal...');
        const withdrawTx = await walletClient.writeContract({
          address: contracts.marginAccount.address,
          abi: contracts.marginAccount.abi,
          functionName: 'withdraw',
          args: [largeWithdrawal]
        });
        
        const receipt = await publicClient.waitForTransactionReceipt({ hash: withdrawTx });
        console.log('✅ Large withdrawal successful!');
        console.log('📋 Transaction Hash:', withdrawTx);
        
      } catch (error) {
        console.log('❌ Large withdrawal failed:', error);
      }
    } else {
      console.log('⚠️  Insufficient free balance for 1000 USDC withdrawal');
      console.log('   Available:', formatUnits(currentFreeBalance, 6), 'USDC');
      
      // Test partial withdrawal of all available free balance
      if (currentFreeBalance > 0n) {
        console.log('\n🔬 Test Case 3: Withdraw All Available Free Balance');
        console.log('   Amount:', formatUnits(currentFreeBalance, 6), 'USDC');
        
        try {
          console.log('🔄 Attempting to withdraw all free balance...');
          const withdrawAllTx = await walletClient.writeContract({
            address: contracts.marginAccount.address,
            abi: contracts.marginAccount.abi,
            functionName: 'withdraw',
            args: [currentFreeBalance]
          });
          
          const receipt = await publicClient.waitForTransactionReceipt({ hash: withdrawAllTx });
          console.log('✅ Full withdrawal successful!');
          console.log('📋 Transaction Hash:', withdrawAllTx);
          
          // Final balance check
          const finalFreeBalance = await publicClient.readContract({
            address: contracts.marginAccount.address,
            abi: contracts.marginAccount.abi,
            functionName: 'freeBalance',
            args: [account.address]
          }) as bigint;
          
          console.log('📊 Final Free Balance:', formatUnits(finalFreeBalance, 6), 'USDC (should be 0)');
          
        } catch (error) {
          console.log('❌ Full withdrawal failed:', error);
        }
      }
    }
    
    // Test Case 4: Test withdrawal of locked balance (should fail)
    console.log('\n🔬 Test Case 4: Attempt to Withdraw Locked Balance (Should Fail)');
    
    const currentLockedBalance = await publicClient.readContract({
      address: contracts.marginAccount.address,
      abi: contracts.marginAccount.abi,
      functionName: 'lockedBalance',
      args: [account.address]
    }) as bigint;
    
    if (currentLockedBalance > 0n) {
      console.log('   Locked Balance:', formatUnits(currentLockedBalance, 6), 'USDC');
      
      try {
        console.log('🔄 Attempting to withdraw locked balance (should fail)...');
        const badWithdrawTx = await walletClient.writeContract({
          address: contracts.marginAccount.address,
          abi: contracts.marginAccount.abi,
          functionName: 'withdraw',
          args: [currentLockedBalance]
        });
        
        await publicClient.waitForTransactionReceipt({ hash: badWithdrawTx });
        console.log('❌ Withdrawal succeeded when it should have failed!');
        
      } catch (error) {
        console.log('✅ Expected failure: Cannot withdraw locked balance');
        console.log('   Error:', error);
      }
    } else {
      console.log('ℹ️  No locked balance to test withdrawal failure');
    }
    
  } catch (error) {
    console.error('❌ Error in withdrawal testing:', error);
  }
  
  console.log('\n🎯 Withdrawal Logic Analysis Complete');
}

testMarginWithdrawal();
