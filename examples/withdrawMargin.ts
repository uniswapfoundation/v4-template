import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain, parseUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

// Basic network config (adjust RPC via env)
const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'http://localhost:8545';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing');

async function main() {
  const amountArg = process.argv[2];
  if (!amountArg) throw new Error('Usage: bun run withdrawMargin <amount_usdc>');
  
  const amount = parseUnits(amountArg, 6); // USDC has 6 decimals
  
  const c = getContracts(CHAIN_ID);
  const account = privateKeyToAccount(PK as `0x${string}`);
  
  const chain = defineChain({
    id: CHAIN_ID,
    name: 'UnichainSepolia',
    nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 },
    rpcUrls: { default: { http: [RPC_URL] }, public: { http: [RPC_URL] } }
  });

  const walletClient = createWalletClient({
    account,
    transport: http(RPC_URL),
    chain
  });

  const publicClient = createPublicClient({
    transport: http(RPC_URL),
    chain
  });

  console.log('Account:', account.address);
  console.log(`Withdrawing USDC from MarginAccount: ${amountArg}`);

  // Check current margin balance before withdrawal
  try {
    const currentBalance = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi,
      functionName: 'getMarginBalance',
      args: [account.address]
    });
    console.log(`Current margin balance: ${currentBalance} USDC (wei)`);
  } catch (error) {
    console.log('Could not fetch current margin balance:', error);
  }

  // Withdraw margin
  try {
    console.log('Withdrawing margin...');
    const withdrawTx = await walletClient.writeContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi,
      functionName: 'withdraw',
      args: [amount]
    });
    
    console.log(`Withdraw tx hash: ${withdrawTx}`);
    
    // Wait for transaction confirmation
    const receipt = await publicClient.waitForTransactionReceipt({ hash: withdrawTx });
    console.log(`Transaction confirmed in block: ${receipt.blockNumber}`);
    
    // Check final margin balance
    const finalBalance = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi,
      functionName: 'getMarginBalance',
      args: [account.address]
    });
    console.log(`Final margin balance: ${finalBalance} USDC (wei)`);
    
  } catch (error) {
    console.log('Failed to withdraw margin:', error);
  }
}

main().catch(console.error);
