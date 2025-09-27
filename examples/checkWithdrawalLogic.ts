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
// Use the actual trading account that has positions
const account = privateKeyToAccount('0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d');

async function checkWithdrawalCapability() {
  console.log('🔍 Checking Free Margin Withdrawal Capability\n');
  
  const publicClient = createPublicClient({ chain: unichainSepolia, transport });
  const walletClient = createWalletClient({ account, chain: unichainSepolia, transport });
  const contracts = getContracts(UNICHAIN_SEPOLIA);
  
  console.log('👤 Trading Account:', account.address);
  console.log('💰 MarginAccount Address:', contracts.marginAccount.address);
  
  try {
    // Step 1: Check current balances
    console.log('\n📊 Current Balance Status:');
    
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
    console.log('  💳 Current Wallet USDC:', formatUnits(walletUSDC, 6), 'USDC');
    
    // Step 2: Analyze withdrawal possibilities
    console.log('\n🧮 Withdrawal Analysis:');
    
    if (freeBalance > 0n) {
      console.log('✅ User CAN withdraw free margin');
      console.log(`   Maximum withdrawable: ${formatUnits(freeBalance, 6)} USDC`);
      
      // Check if there are any restrictions
      console.log('\n🔬 Testing Small Withdrawal (50 USDC):');
      const testAmount = parseUnits('50', 6);
      
      if (freeBalance >= testAmount) {
        try {
          console.log('🔄 Simulating 50 USDC withdrawal...');
          
          // Perform the actual withdrawal
          const withdrawTx = await walletClient.writeContract({
            address: contracts.marginAccount.address,
            abi: contracts.marginAccount.abi,
            functionName: 'withdraw',
            args: [testAmount]
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
          
          console.log('\n📊 Post-Withdrawal Balances:');
          console.log('  💰 New Free Balance:', formatUnits(newFreeBalance, 6), 'USDC');
          console.log('  💳 New Wallet Balance:', formatUnits(newWalletUSDC, 6), 'USDC');
          console.log('  📈 Withdrawn Amount:', formatUnits(freeBalance - newFreeBalance, 6), 'USDC');
          console.log('  📈 Received in Wallet:', formatUnits(newWalletUSDC - walletUSDC, 6), 'USDC');
          
        } catch (error) {
          console.log('❌ Withdrawal failed:', error);
        }
      } else {
        console.log('⚠️  Free balance less than 50 USDC, testing smaller amount...');
        const smallerAmount = freeBalance / 2n; // Withdraw half
        
        if (smallerAmount > 0n) {
          try {
            console.log(`🔄 Withdrawing ${formatUnits(smallerAmount, 6)} USDC...`);
            
            const withdrawTx = await walletClient.writeContract({
              address: contracts.marginAccount.address,
              abi: contracts.marginAccount.abi,
              functionName: 'withdraw',
              args: [smallerAmount]
            });
            
            await publicClient.waitForTransactionReceipt({ hash: withdrawTx });
            console.log('✅ Partial withdrawal successful!');
            
          } catch (error) {
            console.log('❌ Partial withdrawal failed:', error);
          }
        }
      }
      
    } else {
      console.log('❌ User CANNOT withdraw free margin');
      console.log('   Reason: No free balance available');
      
      if (lockedBalance > 0n) {
        console.log('   💡 All balance is locked in active positions');
        console.log('   📝 To withdraw: Close positions or remove margin from positions');
      } else {
        console.log('   💡 No funds in MarginAccount');
        console.log('   📝 To withdraw: Deposit USDC first');
      }
    }
    
    // Step 3: Show withdrawal logic summary
    console.log('\n📋 Withdrawal Logic Summary:');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('✅ Users CAN withdraw free margin directly to their wallet');
    console.log('✅ Function: MarginAccount.withdraw(amount)');
    console.log('✅ Requirement: amount <= freeBalance');
    console.log('❌ Users CANNOT withdraw locked margin (used in active positions)');
    console.log('📝 To free up locked margin: Close positions or use removeMargin()');
    console.log('💰 Current Status:');
    console.log(`   - Free (withdrawable): ${formatUnits(freeBalance, 6)} USDC`);
    console.log(`   - Locked (in positions): ${formatUnits(lockedBalance, 6)} USDC`);
    
  } catch (error) {
    console.error('❌ Error checking withdrawal capability:', error);
  }
}

checkWithdrawalCapability();
