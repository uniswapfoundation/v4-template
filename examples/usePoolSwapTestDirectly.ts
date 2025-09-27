import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain, encodeAbiParameters, keccak256 } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

async function usePoolSwapTestDirectly() {
  console.log('🔄 Using PoolSwapTest to Open Long Position');
  
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

  // Calculate poolId using the same method as Uniswap V4
  const poolKeyEncoded = encodeAbiParameters(
    [
      { type: 'address', name: 'currency0' },
      { type: 'address', name: 'currency1' },
      { type: 'uint24', name: 'fee' },
      { type: 'int24', name: 'tickSpacing' },
      { type: 'address', name: 'hooks' }
    ],
    [currency0, currency1, fee, tickSpacing, hooks]
  );
  const poolId = keccak256(poolKeyEncoded);
  
  console.log('🆔 Pool ID:', poolId);

  try {
    // Parameters
    const marginAmount = 100; // 100 USDC
    const leverage = 5; // 5x leverage
    
    console.log('📊 Position Parameters:');
    console.log('  Margin:', marginAmount, 'USDC');
    console.log('  Leverage:', leverage, 'x');

    // Get current mark price
    const markPrice = await publicClient.readContract({
      address: c.fundingOracle.address,
      abi: c.fundingOracle.abi as any,
      functionName: 'getMarkPrice',
      args: [poolId]
    }) as bigint;
    
    console.log('📊 Current Mark Price:', Number(markPrice) / 1e18, 'USDC per VETH');

    // Calculate position size
    const marginAmount18 = BigInt(marginAmount) * BigInt(1e12); // Convert USDC to 18 decimals
    const leverageAmount18 = BigInt(leverage) * BigInt(1e18);
    const notionalValue = (marginAmount18 * leverageAmount18) / BigInt(1e18);
    const positionSize = (notionalValue * BigInt(1e18)) / markPrice;
    
    console.log('📈 Expected Position Size:', Number(positionSize) / 1e18, 'VETH');
    console.log('💵 Expected Notional Value:', Number(notionalValue) / 1e18, 'USDC');

    // Check USDC balance
    const usdcBalance = await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    });
    console.log('💳 Current USDC Balance:', Number(usdcBalance) / 1e6);

    // Approve USDC for MarginAccount
    console.log('🔄 Approving USDC for MarginAccount...');
    const approveTx = await walletClient.writeContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'approve',
      args: [c.marginAccount.address, BigInt(marginAmount) * BigInt(1e6)]
    });
    
    console.log('⏳ Waiting for approval...');
    await publicClient.waitForTransactionReceipt({ hash: approveTx });
    console.log('✅ USDC approved for MarginAccount');

    // Deposit margin to MarginAccount
    console.log('💰 Depositing margin to MarginAccount...');
    const depositTx = await walletClient.writeContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'deposit',
      args: [BigInt(marginAmount) * BigInt(1e6)]
    });
    
    console.log('⏳ Waiting for margin deposit...');
    await publicClient.waitForTransactionReceipt({ hash: depositTx });
    console.log('✅ Margin deposited successfully');

    // Build hookData for opening position via PoolSwapTest
    const tradeParams: [`0x${string}`, boolean, `0x${string}`, bigint, bigint, bigint] = [
      poolId as `0x${string}`, // marketId
      true, // isLong
      account.address, // trader
      positionSize, // sizeBase
      markPrice, // entryPrice
      BigInt(marginAmount) * BigInt(1e6) // margin in USDC
    ];

    const hookData = encodeAbiParameters(
      [
        { type: 'bytes32', name: 'marketId' },
        { type: 'bool', name: 'isLong' },
        { type: 'address', name: 'trader' },
        { type: 'uint256', name: 'sizeBase' },
        { type: 'uint256', name: 'entryPrice' },
        { type: 'uint256', name: 'margin' }
      ],
      tradeParams
    );

    console.log('🔄 Opening long position via PoolSwapTest with hookData...');

    // Call swap with minimal amount, the real action happens in hook
    const swapTx = await walletClient.writeContract({
      address: c.poolSwapTest.address,
      abi: c.poolSwapTest.abi as any,
      functionName: 'swap',
      args: [
        {
          currency0: currency0,
          currency1: currency1,
          fee: fee,
          tickSpacing: tickSpacing,
          hooks: hooks
        },
        {
          zeroForOne: true,
          amountSpecified: BigInt(1), // Minimal swap amount
          sqrtPriceLimitX96: BigInt("79228162514264337593543950336") // SQRT_PRICE_1_1 equivalent
        },
        {
          takeClaims: false,
          settleUsingBurn: false
        },
        hookData
      ]
    });
    
    console.log('⏳ Waiting for position creation...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash: swapTx });
    
    console.log('🎉 Position opened successfully!');
    console.log('📋 Transaction Hash:', swapTx);
    console.log('📦 Block Number:', receipt.blockNumber);

  } catch (error) {
    console.error('❌ Error:', error);
  }
}

usePoolSwapTestDirectly().catch(e => { 
  console.error('💥 Failed:', e); 
  process.exit(1); 
});
