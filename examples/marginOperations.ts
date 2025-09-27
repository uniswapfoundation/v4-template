// Manage margin deposits and withdrawals
import 'dotenv/config';
import { http, createWalletClient, createPublicClient, parseUnits, defineChain, formatUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

interface MarginOperationResult {
  transactionHash: string;
  blockNumber: bigint;
  previousBalance: string;
  newBalance: string;
  amount: string;
  operation: 'deposit' | 'withdraw';
}

export async function depositMargin(amount: string): Promise<MarginOperationResult> {
  console.log('🏦 Depositing Margin to Account');
  
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

  const depositAmount = parseUnits(amount, 6); // USDC has 6 decimals
  console.log('👤 Account:', account.address);
  console.log('💰 Deposit Amount:', formatUnits(depositAmount, 6), 'USDC');

  try {
    // Check current USDC balance
    const usdcBalance = (await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    })) as bigint;

    console.log('💳 Current USDC Balance:', formatUnits(usdcBalance, 6));

    if (usdcBalance < depositAmount) {
      throw new Error(`Insufficient USDC balance. Need: ${amount}, Have: ${formatUnits(usdcBalance, 6)}`);
    }

    // Get current margin balance
    const currentMargin = (await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'getMargin',
      args: [account.address]
    })) as bigint;

    console.log('🏦 Current Margin Balance:', formatUnits(currentMargin, 6), 'USDC');

    // Check and approve USDC allowance
    const allowance = (await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'allowance',
      args: [account.address, c.marginAccount.address]
    })) as bigint;

    if (allowance < depositAmount) {
      console.log('🔓 Approving USDC for MarginAccount...');
      const approveTx = await walletClient.writeContract({
        address: c.mockUSDC.address,
        abi: c.mockUSDC.abi as any,
        functionName: 'approve',
        args: [c.marginAccount.address, depositAmount]
      });
      
      await publicClient.waitForTransactionReceipt({ hash: approveTx });
      console.log('✅ USDC approved');
    }

    // Deposit margin
    console.log('🔄 Depositing margin...');
    const depositTx = await walletClient.writeContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'depositMargin',
      args: [depositAmount]
    });

    const receipt = await publicClient.waitForTransactionReceipt({ hash: depositTx });
    console.log('✅ Margin deposited successfully!');

    // Get updated margin balance
    const newMargin = (await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'getMargin',
      args: [account.address]
    })) as bigint;

    console.log('🏦 Updated Margin Balance:', formatUnits(newMargin, 6), 'USDC');

    return {
      transactionHash: depositTx,
      blockNumber: receipt.blockNumber,
      previousBalance: formatUnits(currentMargin, 6),
      newBalance: formatUnits(newMargin, 6),
      amount: formatUnits(depositAmount, 6),
      operation: 'deposit'
    };

  } catch (error) {
    console.error('❌ Error depositing margin:', error);
    throw error;
  }
}

export async function withdrawMargin(amount: string): Promise<MarginOperationResult> {
  console.log('🏧 Withdrawing Margin from Account');
  
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

  const withdrawAmount = parseUnits(amount, 6); // USDC has 6 decimals
  console.log('👤 Account:', account.address);
  console.log('💰 Withdrawal Amount:', formatUnits(withdrawAmount, 6), 'USDC');

  try {
    // Get current margin balance
    const currentMargin = (await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'getMargin',
      args: [account.address]
    })) as bigint;

    console.log('🏦 Current Margin Balance:', formatUnits(currentMargin, 6), 'USDC');

    if (currentMargin < withdrawAmount) {
      throw new Error(`Insufficient margin balance. Need: ${amount}, Have: ${formatUnits(currentMargin, 6)}`);
    }

    // Check available margin (not used in positions)
    try {
      const availableMargin = (await publicClient.readContract({
        address: c.marginAccount.address,
        abi: c.marginAccount.abi as any,
        functionName: 'getAvailableMargin',
        args: [account.address]
      })) as bigint;

      console.log('💸 Available Margin (withdrawable):', formatUnits(availableMargin, 6), 'USDC');

      if (availableMargin < withdrawAmount) {
        throw new Error(`Insufficient available margin. Available: ${formatUnits(availableMargin, 6)}, Requested: ${amount}`);
      }
    } catch (error) {
      console.log('ℹ️  Could not check available margin - proceeding with withdrawal attempt');
    }

    // Withdraw margin
    console.log('🔄 Withdrawing margin...');
    const withdrawTx = await walletClient.writeContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'withdrawMargin',
      args: [withdrawAmount]
    });

    const receipt = await publicClient.waitForTransactionReceipt({ hash: withdrawTx });
    console.log('✅ Margin withdrawn successfully!');

    // Get updated margin balance
    const newMargin = (await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'getMargin',
      args: [account.address]
    })) as bigint;

    console.log('🏦 Updated Margin Balance:', formatUnits(newMargin, 6), 'USDC');

    // Get updated USDC balance
    const usdcBalance = (await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    })) as bigint;

    console.log('💳 Updated USDC Balance:', formatUnits(usdcBalance, 6));

    return {
      transactionHash: withdrawTx,
      blockNumber: receipt.blockNumber,
      previousBalance: formatUnits(currentMargin, 6),
      newBalance: formatUnits(newMargin, 6),
      amount: formatUnits(withdrawAmount, 6),
      operation: 'withdraw'
    };

  } catch (error) {
    console.error('❌ Error withdrawing margin:', error);
    throw error;
  }
}

// Execute if run directly
if (require.main === module) {
  const operation = process.argv[2]; // 'deposit' or 'withdraw'
  const amount = process.argv[3]; // Amount in USDC

  if (!operation || !amount) {
    console.log('Usage: npm run margin-operations <deposit|withdraw> <amount>');
    console.log('Example: npm run margin-operations deposit 1000');
    console.log('Example: npm run margin-operations withdraw 500');
    process.exit(1);
  }

  const execute = operation === 'deposit' ? depositMargin : withdrawMargin;
  
  execute(amount)
    .then((result) => {
      console.log('🎉 Margin operation completed successfully!');
      console.log('📊 Result:', result);
    })
    .catch((error) => {
      console.error('💥 Margin operation failed:', error);
      process.exit(1);
    });
}

