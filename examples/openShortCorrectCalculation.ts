import 'do// Get command line arguments
const args = process.argv.slice(2);
if (args.length < 2) {
  console.log('Usage: bun run openShortCorrectCalculation.ts <marginAmount> <leverage>');
  console.log('Example: bun run openShortCorrectCalculation.ts 150 3  # Short with 150 USDC margin at 3x leverage');
  console.log('Note: Minimum margin appears to be ~100 USDC for most position sizes');
  process.exit(1);
}

const marginAmount = parseFloat(args[0]!);
const leverage = parseFloat(args[1]!);

// Validate minimum margin
if (marginAmount < 100) {
  console.log('⚠️  Warning: Margin less than 100 USDC may fail due to InsufficientMargin error');
  console.log('💡 Try using at least 100 USDC margin');
}g';
import { http, createWalletClient, createPublicClient, defineChain, keccak256, encodeAbiParameters } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

// Get command line arguments
const args = process.argv.slice(2);
if (args.length < 2) {
  console.log('Usage: bun run openShortCorrectCalculation.ts <marginUSDC> <leverage>');
  console.log('Example: bun run openShortCorrectCalculation.ts 100 5  # 100 USDC margin at 5x leverage');
  process.exit(1);
}

const marginUSDC = parseFloat(args[0]!);
const leverage = parseFloat(args[1]!);

async function openShortCorrectCalculation() {
  console.log('🔄 Opening Short Position with Correct Calculations');
  
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

  try {
    // Setup pool configuration (same as working scripts)
    const fee = 3000; // 0.3%
    const tickSpacing = 60;
    const hooks = c.perpsHook.address;
    
    console.log('💱 Pool Configuration:');
    console.log('  Currency0:', c.mockVETH.address);
    console.log('  Currency1:', c.mockUSDC.address);
    console.log('  Fee:', fee, 'bps');
    console.log('  Hook:', hooks);

    // Calculate poolId (same method as working scripts)
    const poolKey = encodeAbiParameters(
      [
        { name: 'currency0', type: 'address' },
        { name: 'currency1', type: 'address' },
        { name: 'fee', type: 'uint24' },
        { name: 'tickSpacing', type: 'int24' },
        { name: 'hooks', type: 'address' }
      ],
      [c.mockVETH.address, c.mockUSDC.address, fee, tickSpacing, hooks]
    );
    
    const poolId = keccak256(poolKey);
    console.log('🆔 Pool ID:', poolId);
    
    console.log('📊 Position Parameters:');
    console.log('  Margin:', marginUSDC, 'USDC');
    console.log('  Leverage:', leverage, 'x');

    // Get current mark price for calculations
    const markPrice = await publicClient.readContract({
      address: c.fundingOracle.address,
      abi: c.fundingOracle.abi as any,
      functionName: 'getMarkPrice',
      args: [poolId]
    }) as bigint;
    
    console.log('📊 Current Mark Price:', Number(markPrice) / 1e18, 'USDC per VETH');

    // Calculate position size correctly for SHORT
    // For SHORT: negative sizeBase indicates short position
    const notionalValueUSDC = marginUSDC * leverage; // e.g., 100 * 5 = 500 USDC
    const priceUSDCPerVETH = Number(markPrice) / 1e18; // e.g., 2000 USDC per VETH
    const positionSizeVETH = notionalValueUSDC / priceUSDCPerVETH; // e.g., 500 / 2000 = 0.25 VETH
    
    // Convert to contract units
    const marginAmountWei = BigInt(Math.floor(marginUSDC * 1e6)); // USDC has 6 decimals
    const positionSizeWei = -BigInt(Math.floor(positionSizeVETH * 1e18)); // NEGATIVE for SHORT position
    
    console.log('📉 Expected Position Size:', -positionSizeVETH, 'VETH (SHORT)');
    console.log('💵 Expected Notional Value:', notionalValueUSDC, 'USDC');
    console.log('🔢 Position Size Wei:', positionSizeWei.toString());
    console.log('🔢 Margin Wei:', marginAmountWei.toString());

    // Check USDC balance
    const usdcBalance = await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    }) as bigint;
    
    console.log('💳 Current USDC Balance:', Number(usdcBalance) / 1e6);
    
    if (usdcBalance < marginAmountWei) {
      throw new Error(`Insufficient USDC balance. Need ${marginUSDC} USDC, have ${Number(usdcBalance) / 1e6} USDC`);
    }

    // Step 1: Deposit margin to MarginAccount (following working pattern)
    console.log('💰 Depositing margin to MarginAccount for positioning...');
    
    // Approve USDC for MarginAccount
    const approveTx = await walletClient.writeContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'approve',
      args: [c.marginAccount.address, marginAmountWei]
    });
    await publicClient.waitForTransactionReceipt({ hash: approveTx });
    console.log('✅ USDC approved for MarginAccount');
    
    // Deposit to MarginAccount
    const depositTx = await walletClient.writeContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'deposit',
      args: [marginAmountWei]
    });
    await publicClient.waitForTransactionReceipt({ hash: depositTx });
    console.log('✅ Margin deposited to MarginAccount');

    // Step 2: Open SHORT position via PositionManager
    console.log('🔄 Opening SHORT position via PositionManager...');
    
    const marketId = poolId;
    const sizeBase = positionSizeWei; // NEGATIVE for short position
    const entryPrice = markPrice;
    const margin = marginAmountWei;
    
    console.log('📋 Position Manager Parameters:');
    console.log('  Market ID:', marketId);
    console.log('  Size Base:', sizeBase.toString(), '(negative = SHORT)');
    console.log('  Entry Price:', entryPrice.toString());
    console.log('  Margin:', margin.toString());

    const openPositionTx = await walletClient.writeContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi as any,
      functionName: 'openPosition',
      args: [marketId, sizeBase, entryPrice, margin]
    });
    
    console.log('⏳ Waiting for position creation...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash: openPositionTx });
    
    console.log('🎉 SHORT Position opened successfully!');
    console.log('📋 Transaction Hash:', openPositionTx);
    console.log('📦 Block Number:', receipt.blockNumber);
    
    // Show transaction details
    const logs = receipt.logs;
    console.log('📊 Transaction produced', logs.length, 'events');
    
    console.log('\n📊 Position Summary:');
    console.log('  Type: SHORT');
    console.log('  Size:', Math.abs(positionSizeVETH).toFixed(4), 'VETH');
    console.log('  Margin:', marginUSDC, 'USDC');
    console.log('  Leverage:', leverage + 'x');
    console.log('  Entry Price:', priceUSDCPerVETH, 'USDC per VETH');
    console.log('  Notional Value:', notionalValueUSDC, 'USDC');
    
    console.log('\n💡 Next Steps:');
    console.log('  📊 Check position: bun run showPositions.ts <tokenId>');
    console.log('  📊 Portfolio overview: bun run quickPortfolio.ts');

  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  }
}

openShortCorrectCalculation().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
