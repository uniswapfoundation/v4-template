import 'dotenv/config';
import { http, createWalletClient, createPublicClient, parseUnits, defineChain, formatUnits, encodeAbiParameters, keccak256 } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

async function main() {
  console.log('📈 Opening Long Position via PerpsRouter');
  
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
  console.log('🌐 Chain ID:', CHAIN_ID);
  console.log('🔗 RPC URL:', RPC_URL);

  // Build poolKey struct for VETH-USDC pair
  const fee = 3000; // 0.3%
  const tickSpacing = 60;
  const hooks = c.perpsHook.address;
  
  // Order currencies by address (lower address = currency0)
  const [currency0, currency1] = c.mockUSDC.address.toLowerCase() < c.mockVETH.address.toLowerCase()
    ? [c.mockUSDC.address, c.mockVETH.address]
    : [c.mockVETH.address, c.mockUSDC.address];

  console.log('💱 Pool Configuration:');
  console.log('  Currency0:', currency0);
  console.log('  Currency1:', currency1);
  console.log('  Fee:', fee, 'bps');
  console.log('  Hook:', hooks);

  // Position parameters (can be customized via command line)
  const marginAmount = parseUnits(process.argv[2] || '100', 6); // Default 100 USDC
  const leverage = parseUnits(process.argv[3] || '5', 18); // Default 5x leverage
  const slippageBps = 500n; // 5% slippage tolerance
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 300); // 5 minutes from now

  console.log('📊 Position Parameters:');
  console.log('  Margin:', formatUnits(marginAmount, 6), 'USDC');
  console.log('  Leverage:', formatUnits(leverage, 18), 'x');
  console.log('  Slippage:', Number(slippageBps) / 100, '%');

  try {
    // Check current USDC balance
    const usdcBalance = (await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    })) as bigint;

    console.log('💳 Current USDC Balance:', formatUnits(usdcBalance, 6));

    if (usdcBalance < marginAmount) {
      throw new Error(`Insufficient USDC balance. Need: ${formatUnits(marginAmount, 6)}, Have: ${formatUnits(usdcBalance, 6)}`);
    }

    // Approve USDC for PerpsRouter
    const allowance = (await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'allowance',
      args: [account.address, c.perpsRouter.address]
    })) as bigint;

    if (allowance < marginAmount) {
      console.log('🔓 Approving USDC for PerpsRouter...');
      const approveTx = await walletClient.writeContract({
        address: c.mockUSDC.address,
        abi: c.mockUSDC.abi as any,
        functionName: 'approve',
        args: [c.perpsRouter.address, marginAmount]
      });
      
      console.log('⏳ Waiting for approval confirmation...');
      await publicClient.waitForTransactionReceipt({ hash: approveTx });
      console.log('✅ USDC approved for PerpsRouter');
    }

    // Get current mark price to display expected position size
    console.log('🔍 Testing FundingOracle getMarkPrice...');
    try {
      const poolId = keccak256(encodeAbiParameters([
        { type: 'address', name: 'currency0' },
        { type: 'address', name: 'currency1' },
        { type: 'uint24', name: 'fee' },
        { type: 'int24', name: 'tickSpacing' },
        { type: 'address', name: 'hooks' }
      ], [currency0, currency1, fee, tickSpacing, hooks]));
      
      console.log('🆔 Pool ID for oracle:', poolId);
      
      const markPrice = (await publicClient.readContract({
        address: c.fundingOracle.address,
        abi: c.fundingOracle.abi as any,
        functionName: 'getMarkPrice',
        args: [poolId]
      })) as bigint;
      
      console.log('📊 Current Mark Price:', formatUnits(markPrice, 18), 'USDC per VETH');
      
      // Calculate expected position size
      const notionalSize = (Number(formatUnits(marginAmount, 6)) * Number(formatUnits(leverage, 18)));
      const baseSize = notionalSize / Number(formatUnits(markPrice, 18));
      console.log('📈 Expected Position Size:', baseSize.toFixed(4), 'VETH');
      console.log('💵 Expected Notional Value:', notionalSize.toFixed(2), 'USDC');
      
    } catch (error) {
      console.log('❌ Error calling FundingOracle.getMarkPrice:', error);
      console.log('ℹ️  This might be the source of the openPosition error');
      throw new Error('FundingOracle not configured properly for this market');
    }

    console.log('🔄 Opening long position via PerpsRouter...');

    // Prepare OpenPositionParams
    const openPositionParams = {
      poolKey: {
        currency0,
        currency1,
        fee,
        tickSpacing,
        hooks
      },
      isLong: true,
      marginAmount,
      leverage,
      slippageBps,
      deadline
    };

    // Open position using PerpsRouter
    const txHash = await walletClient.writeContract({
      address: c.perpsRouter.address,
      abi: c.perpsRouter.abi as any,
      functionName: 'openPosition',
      args: [openPositionParams]
    });

    console.log('⏳ Waiting for transaction confirmation...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
    
    console.log('✅ Position opened successfully!');
    console.log('📋 Transaction Hash:', txHash);
    console.log('📦 Block Number:', receipt.blockNumber);

    // Parse logs to get the token ID
    try {
      // Look for PositionOpened event in the logs
      const positionOpenedLogs = receipt.logs.filter(log => 
        log.address.toLowerCase() === c.perpsRouter.address.toLowerCase()
      );
      
      if (positionOpenedLogs.length > 0) {
        console.log('📜 Found position opened events in transaction logs');
        // Additional parsing could be done here to extract tokenId
      }
    } catch (error) {
      console.log('ℹ️  Could not parse transaction logs for tokenId');
    }

    // Get updated USDC balance
    const updatedBalance = (await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    })) as bigint;

    console.log('💳 Updated USDC Balance:', formatUnits(updatedBalance, 6));
    console.log('💰 Used Margin:', formatUnits(usdcBalance - updatedBalance, 6), 'USDC');

    console.log('🎉 Long position opened successfully via PerpsRouter!');
    
  } catch (error) {
    console.error('❌ Error opening position:', error);
    throw error;
  }
}

// Execute with error handling
main().catch(e => { 
  console.error('💥 Failed to open position:', e); 
  process.exit(1); 
});
