import { createPublicClient, createWalletClient, http, parseUnits, formatUnits, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

// Use the same PK logic as other scripts
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;

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

async function analyzeWithdrawalLogic() {
  console.log('🔍 Analyzing Free Margin Withdrawal Logic\n');
  
  const account = privateKeyToAccount(PK as `0x${string}`);
  const publicClient = createPublicClient({ chain: unichainSepolia, transport });
  const walletClient = createWalletClient({ account, chain: unichainSepolia, transport });
  const contracts = getContracts(UNICHAIN_SEPOLIA);
  
  console.log('👤 Current Portfolio Account:', account.address);
  console.log('💰 MarginAccount Contract:', contracts.marginAccount.address);
  
  try {
    // Get comprehensive balance information
    console.log('\n📊 Complete Balance Analysis:');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
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
    
    const totalMarginBalance = await publicClient.readContract({
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
    
    console.log('📈 Margin Account Breakdown:');
    console.log(`  💰 Free Balance (withdrawable): ${formatUnits(freeBalance, 6)} USDC`);
    console.log(`  🔒 Locked Balance (in positions): ${formatUnits(lockedBalance, 6)} USDC`);
    console.log(`  📊 Total in MarginAccount: ${formatUnits(totalMarginBalance, 6)} USDC`);
    console.log(`  💳 Wallet USDC Balance: ${formatUnits(walletUSDC, 6)} USDC`);
    
    // Withdrawal capability analysis
    console.log('\n🎯 Withdrawal Capability Analysis:');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    if (freeBalance > 0n) {
      console.log('✅ FREE MARGIN WITHDRAWAL: AVAILABLE');
      console.log(`   Maximum withdrawable: ${formatUnits(freeBalance, 6)} USDC`);
      console.log('   Method: MarginAccount.withdraw(amount)');
      console.log('   Restriction: amount <= freeBalance');
      console.log('   Destination: User\'s wallet address');
      
      // Test small withdrawal capability
      const testAmount = parseUnits('100', 6);
      if (freeBalance >= testAmount) {
        console.log('\n🧪 Testing 100 USDC Withdrawal:');
        
        try {
          // Simulate the withdrawal
          console.log('🔄 Executing withdrawal...');
          const withdrawTx = await walletClient.writeContract({
            address: contracts.marginAccount.address,
            abi: contracts.marginAccount.abi,
            functionName: 'withdraw',
            args: [testAmount]
          });
          
          const receipt = await publicClient.waitForTransactionReceipt({ hash: withdrawTx });
          console.log('✅ Withdrawal successful!');
          console.log(`📋 Transaction: ${withdrawTx}`);
          console.log(`📦 Block: ${receipt.blockNumber}`);
          
          // Check post-withdrawal balances
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
          
          console.log('\n📊 Post-Withdrawal Status:');
          console.log(`  💰 New Free Balance: ${formatUnits(newFreeBalance, 6)} USDC`);
          console.log(`  💳 New Wallet Balance: ${formatUnits(newWalletUSDC, 6)} USDC`);
          console.log(`  📉 Balance Reduction: ${formatUnits(freeBalance - newFreeBalance, 6)} USDC`);
          console.log(`  📈 Wallet Increase: ${formatUnits(newWalletUSDC - walletUSDC, 6)} USDC`);
          
        } catch (error) {
          console.log('❌ Withdrawal test failed:', error);
        }
      } else {
        console.log(`\n⚠️  Available balance (${formatUnits(freeBalance, 6)} USDC) < test amount (100 USDC)`);
        
        // Try withdrawing 50% of available balance
        const partialAmount = freeBalance / 2n;
        if (partialAmount > 0n) {
          console.log(`🧪 Testing partial withdrawal: ${formatUnits(partialAmount, 6)} USDC`);
          
          try {
            const withdrawTx = await walletClient.writeContract({
              address: contracts.marginAccount.address,
              abi: contracts.marginAccount.abi,
              functionName: 'withdraw',
              args: [partialAmount]
            });
            
            await publicClient.waitForTransactionReceipt({ hash: withdrawTx });
            console.log('✅ Partial withdrawal successful!');
            
          } catch (error) {
            console.log('❌ Partial withdrawal failed:', error);
          }
        }
      }
      
    } else {
      console.log('❌ FREE MARGIN WITHDRAWAL: NOT AVAILABLE');
      console.log('   Reason: No free balance (freeBalance = 0)');
      
      if (lockedBalance > 0n) {
        console.log('\n💡 Locked Balance Available:');
        console.log(`   Amount: ${formatUnits(lockedBalance, 6)} USDC`);
        console.log('   Status: Cannot be withdrawn directly');
        console.log('   To unlock: Close positions or remove margin from positions');
        console.log('   Methods: closePosition() or removeMargin()');
      } else {
        console.log('\n💡 No Funds in MarginAccount');
        console.log('   Solution: Deposit USDC to MarginAccount first');
        console.log('   Method: MarginAccount.deposit(amount)');
      }
    }
    
    // Overall system logic explanation
    console.log('\n📚 Withdrawal System Logic:');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('🔹 MarginAccount has two balance types:');
    console.log('   • Free Balance: Available for withdrawal');
    console.log('   • Locked Balance: Used as margin for active positions');
    console.log('');
    console.log('🔹 Withdrawal Rules:');
    console.log('   ✅ Can withdraw: freeBalance amount');
    console.log('   ❌ Cannot withdraw: lockedBalance amount');
    console.log('   🔄 To free locked balance: Close/reduce positions');
    console.log('');
    console.log('🔹 Withdrawal Process:');
    console.log('   1. Check freeBalance >= withdrawal amount');
    console.log('   2. Call MarginAccount.withdraw(amount)');
    console.log('   3. USDC transferred from MarginAccount to user wallet');
    console.log('   4. freeBalance reduced by withdrawal amount');
    console.log('');
    console.log('🔹 Current Status Summary:');
    console.log(`   • Withdrawable: ${formatUnits(freeBalance, 6)} USDC`);
    console.log(`   • Locked in positions: ${formatUnits(lockedBalance, 6)} USDC`);
    console.log(`   • Total available: ${formatUnits(totalMarginBalance, 6)} USDC`);
    
  } catch (error) {
    console.error('❌ Error in withdrawal analysis:', error);
  }
}

analyzeWithdrawalLogic();
