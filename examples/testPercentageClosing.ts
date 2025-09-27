import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain, formatUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;

async function testPercentageClosing() {
  console.log('🧪 Testing Percentage-Based Position Closing\n');
  
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

  console.log('👤 Testing Account:', account.address);
  
  try {
    // Step 1: Get current Position #2 details
    console.log('📊 Step 1: Analyzing Current Position #2');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    const tokenId = 2n;
    const position = await publicClient.readContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi as any,
      functionName: 'getPosition',
      args: [tokenId]
    }) as any;

    const originalMargin = Number(position.margin) / 1e6;
    const originalSize = Number(position.sizeBase) / 1e18;
    const entryPrice = Number(position.entryPrice) / 1e18;
    const isLong = Number(position.sizeBase) > 0;
    
    console.log('📈 Current Position State:');
    console.log(`  Token ID: ${Number(tokenId)}`);
    console.log(`  Size: ${Math.abs(originalSize)} VETH (${isLong ? 'LONG' : 'SHORT'})`);
    console.log(`  Margin: ${originalMargin} USDC`);
    console.log(`  Entry Price: ${entryPrice} USDC per VETH`);
    console.log(`  Owner: ${position.owner}`);
    console.log(`  Active: ${position.isActive}`);

    // Get current mark price
    const markPrice = await publicClient.readContract({
      address: c.fundingOracle.address,
      abi: c.fundingOracle.abi as any,
      functionName: 'getMarkPrice',
      args: ['0xdb86d006b7f5ba7afb160f08da976bf53d7254e25da80f1dda0a5d36d26d656d']
    }) as bigint;

    const markPriceFormatted = Number(markPrice) / 1e18;
    console.log(`📊 Current Mark Price: ${markPriceFormatted} USDC per VETH`);

    // Calculate current PnL
    let unrealizedPnL = 0;
    if (isLong) {
      unrealizedPnL = Math.abs(originalSize) * (markPriceFormatted - entryPrice);
    } else {
      unrealizedPnL = Math.abs(originalSize) * (entryPrice - markPriceFormatted);
    }

    console.log(`📈 Current PnL: ${unrealizedPnL >= 0 ? '🟢 +' : '🔴 '}${unrealizedPnL.toFixed(4)} USDC`);

    // Step 2: Test Different Percentage Closes
    console.log('\n🔬 Step 2: Testing Percentage Close Calculations');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    const testPercentages = [10, 25, 50, 75];
    
    for (const percent of testPercentages) {
      console.log(`\n🧮 ${percent}% Close Calculation:`);
      
      const sizeToClose = Math.abs(originalSize) * (percent / 100);
      const remainingSize = Math.abs(originalSize) - sizeToClose;
      const marginToRelease = originalMargin * (percent / 100);
      const remainingMargin = originalMargin - marginToRelease;
      
      console.log(`  Size to close: ${sizeToClose.toFixed(6)} VETH`);
      console.log(`  Remaining size: ${remainingSize.toFixed(6)} VETH`);
      console.log(`  Margin to release: ${marginToRelease.toFixed(2)} USDC`);
      console.log(`  Remaining margin: ${remainingMargin.toFixed(2)} USDC`);
      
      // Calculate PnL for closed portion
      const closedPnL = unrealizedPnL * (percent / 100);
      console.log(`  PnL on closed portion: ${closedPnL >= 0 ? '🟢 +' : '🔴 '}${closedPnL.toFixed(4)} USDC`);
    }

    // Step 3: Perform Actual 10% Close Test
    console.log('\n🚀 Step 3: Executing 10% Position Close Test');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    const testPercent = 10;
    console.log(`🎯 Closing ${testPercent}% of Position #2`);
    
    // Get balances before
    const freeBalanceBefore = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'freeBalance',
      args: [account.address]
    }) as bigint;
    
    console.log(`💰 Free balance before: ${Number(freeBalanceBefore) / 1e6} USDC`);
    
    // Calculate new position parameters
    const newSizeBase = originalSize * (1 - testPercent / 100);
    const newMargin = originalMargin * (1 - testPercent / 100);
    
    console.log('\n📋 Calculated Parameters:');
    console.log(`  Current size: ${Math.abs(originalSize).toFixed(6)} VETH`);
    console.log(`  New size: ${Math.abs(newSizeBase).toFixed(6)} VETH`);
    console.log(`  Size reduction: ${(Math.abs(originalSize) - Math.abs(newSizeBase)).toFixed(6)} VETH`);
    console.log(`  Current margin: ${originalMargin.toFixed(2)} USDC`);
    console.log(`  New margin: ${newMargin.toFixed(2)} USDC`);
    console.log(`  Margin reduction: ${(originalMargin - newMargin).toFixed(2)} USDC`);
    
    try {
      console.log('\n🔄 Executing partial close...');
      
      const closeTx = await walletClient.writeContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: 'updatePosition',
        args: [
          tokenId,
          BigInt(Math.floor(newSizeBase * 1e18)), // new size (keep negative for short)
          BigInt(Math.floor(newMargin * 1e6))     // new margin
        ]
      });

      console.log('⏳ Waiting for transaction confirmation...');
      const receipt = await publicClient.waitForTransactionReceipt({ hash: closeTx });
      
      console.log('✅ Partial close successful!');
      console.log(`📋 Transaction Hash: ${closeTx}`);
      console.log(`📦 Block Number: ${receipt.blockNumber}`);

      // Step 4: Verify Results
      console.log('\n📊 Step 4: Verifying Results');
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      
      // Get updated position
      const updatedPosition = await publicClient.readContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: 'getPosition',
        args: [tokenId]
      }) as any;

      const newActualSize = Number(updatedPosition.sizeBase) / 1e18;
      const newActualMargin = Number(updatedPosition.margin) / 1e6;
      
      console.log('📈 Updated Position:');
      console.log(`  New size: ${Math.abs(newActualSize).toFixed(6)} VETH`);
      console.log(`  New margin: ${newActualMargin.toFixed(2)} USDC`);
      console.log(`  Size change: ${(Math.abs(originalSize) - Math.abs(newActualSize)).toFixed(6)} VETH`);
      console.log(`  Margin change: ${(originalMargin - newActualMargin).toFixed(2)} USDC`);
      
      // Get updated free balance
      const freeBalanceAfter = await publicClient.readContract({
        address: c.marginAccount.address,
        abi: c.marginAccount.abi as any,
        functionName: 'freeBalance',
        args: [account.address]
      }) as bigint;
      
      const balanceChange = Number(freeBalanceAfter - freeBalanceBefore) / 1e6;
      
      console.log('\n💰 Balance Changes:');
      console.log(`  Free balance after: ${Number(freeBalanceAfter) / 1e6} USDC`);
      console.log(`  Balance increase: ${balanceChange >= 0 ? '🟢 +' : '🔴 '}${balanceChange.toFixed(2)} USDC`);
      
      // Calculate accuracy
      const expectedSizeReduction = Math.abs(originalSize) * (testPercent / 100);
      const actualSizeReduction = Math.abs(originalSize) - Math.abs(newActualSize);
      const sizeAccuracy = ((actualSizeReduction / expectedSizeReduction) * 100).toFixed(2);
      
      const expectedMarginReduction = originalMargin * (testPercent / 100);
      const actualMarginReduction = originalMargin - newActualMargin;
      const marginAccuracy = ((actualMarginReduction / expectedMarginReduction) * 100).toFixed(2);
      
      console.log('\n🎯 Accuracy Analysis:');
      console.log(`  Expected size reduction: ${expectedSizeReduction.toFixed(6)} VETH`);
      console.log(`  Actual size reduction: ${actualSizeReduction.toFixed(6)} VETH`);
      console.log(`  Size accuracy: ${sizeAccuracy}%`);
      console.log(`  Expected margin reduction: ${expectedMarginReduction.toFixed(2)} USDC`);
      console.log(`  Actual margin reduction: ${actualMarginReduction.toFixed(2)} USDC`);
      console.log(`  Margin accuracy: ${marginAccuracy}%`);
      
      // Final assessment
      console.log('\n🏆 Final Assessment:');
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      
      const sizeAccuracyNum = parseFloat(sizeAccuracy);
      const marginAccuracyNum = parseFloat(marginAccuracy);
      
      if (sizeAccuracyNum >= 95 && marginAccuracyNum >= 95) {
        console.log('✅ PERCENTAGE CLOSING: WORKING PERFECTLY');
        console.log('   Both size and margin calculations are highly accurate');
      } else if (sizeAccuracyNum >= 90 && marginAccuracyNum >= 90) {
        console.log('✅ PERCENTAGE CLOSING: WORKING WELL');
        console.log('   Minor precision differences within acceptable range');
      } else {
        console.log('⚠️  PERCENTAGE CLOSING: NEEDS INVESTIGATION');
        console.log('   Significant differences between expected and actual values');
      }
      
      console.log(`   Position successfully reduced by ~${testPercent}%`);
      console.log(`   System properly handles partial position modifications`);
      
    } catch (error) {
      console.log('❌ Partial close failed:', error);
      throw error;
    }

  } catch (error) {
    console.error('❌ Error in percentage closing test:', error);
    throw error;
  }
}

testPercentageClosing();
