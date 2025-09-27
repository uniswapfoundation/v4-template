import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain, formatUnits, parseUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;

async function debugPositionUpdate() {
  console.log('🔍 Debugging Position Update Logic\n');
  
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

  console.log('👤 Account:', account.address);
  
  try {
    const tokenId = 2n;
    
    // Step 1: Get current position details
    console.log('📊 Step 1: Current Position Analysis');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    const position = await publicClient.readContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi as any,
      functionName: 'getPosition',
      args: [tokenId]
    }) as any;

    const currentSize = Number(position.sizeBase) / 1e18;
    const currentMargin = Number(position.margin) / 1e6;
    
    console.log('📈 Current Position:');
    console.log(`  Size: ${currentSize} VETH`);
    console.log(`  Margin: ${currentMargin} USDC`);
    console.log(`  Owner: ${position.owner}`);
    console.log(`  Entry Price: ${Number(position.entryPrice) / 1e18} USDC`);
    
    // Step 2: Test direct position update with specific values
    console.log('\n🧪 Step 2: Direct Position Update Test');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    // Let's try reducing the position to exactly half
    const targetSize = currentSize * 0.5;
    const targetMargin = currentMargin * 0.5;
    
    console.log('🎯 Target Values:');
    console.log(`  Target Size: ${targetSize} VETH`);
    console.log(`  Target Margin: ${targetMargin} USDC`);
    
    // Convert to contract values
    const newSizeBase = BigInt(Math.floor(targetSize * 1e18));
    const newMargin = BigInt(Math.floor(targetMargin * 1e6));
    
    console.log('🔧 Contract Parameters:');
    console.log(`  newSizeBase: ${newSizeBase.toString()}`);
    console.log(`  newMargin: ${newMargin.toString()}`);
    
    // Get min margin requirement from PositionManager
    const minMargin = await publicClient.readContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi as any,
      functionName: 'minMargin',
      args: []
    }) as bigint;
    
    console.log(`📏 Min Margin Requirement: ${Number(minMargin) / 1e6} USDC`);
    
    if (newMargin < minMargin) {
      console.log('⚠️  Target margin is below minimum requirement!');
      console.log(`   Target: ${Number(newMargin) / 1e6} USDC`);
      console.log(`   Required: ${Number(minMargin) / 1e6} USDC`);
      return;
    }
    
    // Step 3: Execute the update
    console.log('\n🚀 Step 3: Executing Position Update');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    try {
      console.log('🔄 Calling updatePosition...');
      
      const updateTx = await walletClient.writeContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: 'updatePosition',
        args: [tokenId, newSizeBase, newMargin]
      });

      console.log('⏳ Waiting for confirmation...');
      const receipt = await publicClient.waitForTransactionReceipt({ hash: updateTx });
      
      console.log('✅ Update transaction successful!');
      console.log(`📋 Transaction: ${updateTx}`);
      console.log(`📦 Block: ${receipt.blockNumber}`);
      
      // Step 4: Verify the update
      console.log('\n📊 Step 4: Verification');
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      
      const updatedPosition = await publicClient.readContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: 'getPosition',
        args: [tokenId]
      }) as any;

      const newActualSize = Number(updatedPosition.sizeBase) / 1e18;
      const newActualMargin = Number(updatedPosition.margin) / 1e6;
      
      console.log('📈 Updated Position:');
      console.log(`  Size: ${newActualSize} VETH (was ${currentSize})`);
      console.log(`  Margin: ${newActualMargin} USDC (was ${currentMargin})`);
      console.log(`  Size Change: ${newActualSize - currentSize} VETH`);
      console.log(`  Margin Change: ${newActualMargin - currentMargin} USDC`);
      
      // Calculate accuracy
      const sizeAccuracy = Math.abs(newActualSize - targetSize) < 0.001;
      const marginAccuracy = Math.abs(newActualMargin - targetMargin) < 0.01;
      
      console.log('\n🎯 Accuracy Check:');
      console.log(`  Size Accuracy: ${sizeAccuracy ? '✅' : '❌'} (target: ${targetSize}, actual: ${newActualSize})`);
      console.log(`  Margin Accuracy: ${marginAccuracy ? '✅' : '❌'} (target: ${targetMargin}, actual: ${newActualMargin})`);
      
      if (sizeAccuracy && marginAccuracy) {
        console.log('\n🏆 SUCCESS: Position update working correctly!');
      } else {
        console.log('\n⚠️  ISSUE: Position update not achieving target values');
      }
      
    } catch (error) {
      console.log('❌ Update failed:', error);
      
      // Let's check if there are specific constraints
      console.log('\n🔍 Constraint Analysis:');
      
      // Check if user owns the position
      if (position.owner.toLowerCase() !== account.address.toLowerCase()) {
        console.log('❌ Ownership issue: User does not own position');
      }
      
      // Check if position is active
      if (!position.isActive) {
        console.log('❌ Position is not active');
      }
      
      // Check margin constraints
      if (newMargin < minMargin) {
        console.log('❌ Margin below minimum requirement');
      }
      
      // Check size constraints
      if (newSizeBase === 0n) {
        console.log('❌ Size cannot be zero (use closePosition instead)');
      }
    }
    
  } catch (error) {
    console.error('❌ Error in position update debugging:', error);
  }
}

debugPositionUpdate();
