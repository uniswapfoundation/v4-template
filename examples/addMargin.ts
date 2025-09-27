import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

// Get command line arguments
const args = process.argv.slice(2);
if (args.length < 2) {
  console.log('Usage: bun run addMargin.ts <tokenId> <marginAmount>');
  console.log('Example: bun run addMargin.ts 1 100  # Add 100 USDC margin to position 1');
  process.exit(1);
}

const tokenId = BigInt(args[0]!);
const marginAmount = parseFloat(args[1]!);

async function addMarginToPosition() {
  console.log('💰 Adding Margin to Position');
  
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

  console.log('👤 Using account:', account.address);
  console.log('🏷️  Position Token ID:', Number(tokenId));
  console.log('💵 Margin to add:', marginAmount, 'USDC');

  try {
    // Get position details first
    const position = await publicClient.readContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi as any,
      functionName: 'getPosition',
      args: [tokenId]
    }) as any;

    console.log('\n📊 Current Position:');
    const currentMargin = Number(position.margin) / 1e6;
    const sizeBase = Number(position.sizeBase) / 1e18;
    const entryPrice = Number(position.entryPrice) / 1e18;
    const isLong = Number(position.sizeBase) > 0;
    
    console.log(`  Current Margin: ${currentMargin} USDC`);
    console.log(`  Size: ${Math.abs(sizeBase)} VETH (${isLong ? 'LONG' : 'SHORT'})`);
    console.log(`  Entry Price: ${entryPrice} USDC per VETH`);

    // Verify ownership
    if (position.owner.toLowerCase() !== account.address.toLowerCase()) {
      throw new Error('You do not own this position');
    }

    // Convert margin amount to wei (6 decimals for USDC)
    const marginWei = BigInt(Math.floor(marginAmount * 1e6));

    // Check current balances
    const usdcBalance = await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    }) as bigint;

    console.log(`\n💳 Current USDC Balance: ${Number(usdcBalance) / 1e6}`);

    if (usdcBalance < marginWei) {
      throw new Error(`Insufficient USDC balance. Need ${marginAmount} USDC, have ${Number(usdcBalance) / 1e6} USDC`);
    }

    // Step 1: Approve USDC for MarginAccount
    console.log('\n🔐 Approving USDC for MarginAccount...');
    
    const approveTx = await walletClient.writeContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'approve',
      args: [c.marginAccount.address, marginWei]
    });

    await publicClient.waitForTransactionReceipt({ hash: approveTx });
    console.log('✅ USDC approved for MarginAccount');

    // Step 2: Deposit margin to MarginAccount
    console.log('💰 Depositing margin to MarginAccount...');
    
    const depositTx = await walletClient.writeContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'deposit',
      args: [marginWei]
    });

    await publicClient.waitForTransactionReceipt({ hash: depositTx });
    console.log('✅ Margin deposited to MarginAccount');

    // Step 3: Add margin to position
    console.log('🔄 Adding margin to position...');
    
    const addMarginTx = await walletClient.writeContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi as any,
      functionName: 'addMargin',
      args: [tokenId, marginWei]
    });

    console.log('⏳ Waiting for margin addition...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash: addMarginTx });
    
    console.log('🎉 Margin added successfully!');
    console.log('📋 Transaction Hash:', addMarginTx);
    console.log('📦 Block Number:', receipt.blockNumber);

    // Get updated position details
    const updatedPosition = await publicClient.readContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi as any,
      functionName: 'getPosition',
      args: [tokenId]
    }) as any;

    const newMargin = Number(updatedPosition.margin) / 1e6;
    const notionalValue = Math.abs(sizeBase) * entryPrice;
    const newLeverage = notionalValue / newMargin;

    console.log('\n📊 Updated Position:');
    console.log(`  Previous Margin: ${currentMargin} USDC`);
    console.log(`  New Margin: ${newMargin} USDC`);
    console.log(`  Margin Added: +${marginAmount} USDC`);
    console.log(`  New Leverage: ${newLeverage.toFixed(2)}x`);
    console.log(`  Notional Value: ${notionalValue.toFixed(2)} USDC`);

  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  }
}

addMarginToPosition().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
