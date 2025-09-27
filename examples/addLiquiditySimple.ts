// Add liquidity to the VETH-USDC pool using PoolModifyLiquidityTest
import 'dotenv/config';
import { http, createWalletClient, createPublicClient, parseUnits, defineChain, formatUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

// Liquidity parameters
const LIQUIDITY_USDC_AMOUNT = parseUnits('10000', 6); // 10,000 USDC
const LIQUIDITY_VETH_AMOUNT = parseUnits('10', 18); // 10 VETH
const TICK_LOWER = -600; // Wider range for more liquidity
const TICK_UPPER = 600;

async function main() {
  console.log('💧 Adding Liquidity to VETH-USDC Pool');
  
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

  // Order currencies by address (lower address = currency0)
  const [currency0, currency1] = c.mockUSDC.address.toLowerCase() < c.mockVETH.address.toLowerCase()
    ? [c.mockUSDC.address, c.mockVETH.address]
    : [c.mockVETH.address, c.mockUSDC.address];

  console.log('💱 Pool Configuration:');
  console.log('  Currency0:', currency0);
  console.log('  Currency1:', currency1);
  console.log('  Fee: 3000 bps');
  console.log('  Hook:', c.perpsHook.address);

  console.log('💰 Liquidity Parameters:');
  console.log('  USDC Amount:', formatUnits(LIQUIDITY_USDC_AMOUNT, 6));
  console.log('  VETH Amount:', formatUnits(LIQUIDITY_VETH_AMOUNT, 18));
  console.log('  Tick Range:', TICK_LOWER, 'to', TICK_UPPER);

  try {
    // Check current balances
    const usdcBalance = (await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    })) as bigint;

    const vethBalance = (await publicClient.readContract({
      address: c.mockVETH.address,
      abi: c.mockVETH.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    })) as bigint;

    console.log('💳 Current Balances:');
    console.log('  USDC:', formatUnits(usdcBalance, 6));
    console.log('  VETH:', formatUnits(vethBalance, 18));

    if (usdcBalance < LIQUIDITY_USDC_AMOUNT || vethBalance < LIQUIDITY_VETH_AMOUNT) {
      throw new Error('Insufficient token balances for liquidity provision');
    }

    // Approve tokens for PoolModifyLiquidityTest
    console.log('🔓 Approving tokens...');
    
    const usdcApproveTx = await walletClient.writeContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'approve',
      args: [c.poolModifyLiquidityTest.address, LIQUIDITY_USDC_AMOUNT]
    });
    await publicClient.waitForTransactionReceipt({ hash: usdcApproveTx });

    const vethApproveTx = await walletClient.writeContract({
      address: c.mockVETH.address,
      abi: c.mockVETH.abi as any,
      functionName: 'approve',
      args: [c.poolModifyLiquidityTest.address, LIQUIDITY_VETH_AMOUNT]
    });
    await publicClient.waitForTransactionReceipt({ hash: vethApproveTx });
    console.log('✅ Tokens approved');

    // Create pool key
    const poolKey = {
      currency0: currency0 as `0x${string}`,
      currency1: currency1 as `0x${string}`,
      fee: 3000,
      tickSpacing: 60,
      hooks: c.perpsHook.address
    };

    // Create modify liquidity parameters
    const liquidityDelta = parseUnits('1000', 18); // Amount of liquidity to add
    const modifyLiquidityParams = {
      tickLower: TICK_LOWER,
      tickUpper: TICK_UPPER,
      liquidityDelta: liquidityDelta,
      salt: "0x0000000000000000000000000000000000000000000000000000000000000000"
    };

    const hookData = "0x"; // Empty hook data for liquidity operations

    console.log('🔄 Adding liquidity...');
    const liquidityTx = await walletClient.writeContract({
      address: c.poolModifyLiquidityTest.address,
      abi: c.poolModifyLiquidityTest.abi as any,
      functionName: 'modifyLiquidity',
      args: [poolKey, modifyLiquidityParams, hookData]
    });

    console.log('⏳ Waiting for liquidity addition confirmation...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash: liquidityTx });
    
    console.log('✅ Liquidity added successfully!');
    console.log('📋 Transaction Hash:', liquidityTx);
    console.log('📦 Block Number:', receipt.blockNumber);

    // Check updated balances
    const updatedUsdcBalance = (await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    })) as bigint;

    const updatedVethBalance = (await publicClient.readContract({
      address: c.mockVETH.address,
      abi: c.mockVETH.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    })) as bigint;

    console.log('💳 Updated Balances:');
    console.log('  USDC:', formatUnits(updatedUsdcBalance, 6));
    console.log('  VETH:', formatUnits(updatedVethBalance, 18));

    console.log('🎉 Liquidity addition complete! Pool ready for trading.');
    
  } catch (error) {
    console.error('❌ Error adding liquidity:', error);
    throw error;
  }
}

// Execute with error handling
main().catch(e => { 
  console.error('💥 Failed to add liquidity:', e); 
  process.exit(1); 
});
