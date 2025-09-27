import 'dotenv/config';
import { http, createWalletClient, createPublicClient, parseUnits, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

// Basic network config (adjust RPC via env)
const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'http://localhost:8545';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing');

async function main() {
  const account = privateKeyToAccount(PK as `0x${string}`);
  const contracts = getContracts(CHAIN_ID);

  const transport = http(RPC_URL);
  const chain = defineChain({ id: CHAIN_ID, name: 'UnichainSepolia', nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 }, rpcUrls: { default: { http: [RPC_URL] }, public: { http: [RPC_URL] } } });
  const publicClient = createPublicClient({ transport, chain });
  const walletClient = createWalletClient({ account, transport, chain });

  const amountInput = process.argv[2] || '1000'; // USDC (no decimals) e.g. 1000 = 1000 USDC
  const amount = parseUnits(amountInput, 6); // USDC 6 decimals

  console.log('Account:', account.address);
  console.log('Depositing USDC to MarginAccount:', amountInput);

  // Approve if needed (PerpsRouter & MarginAccount pattern). We'll check allowance to MarginAccount only for simplicity.
  const usdc = contracts.mockUSDC;
  const margin = contracts.marginAccount;

  const allowance = (await publicClient.readContract({
    address: usdc.address,
    abi: usdc.abi as any,
    functionName: 'allowance',
    args: [account.address, margin.address]
  })) as bigint;

  if (allowance < amount) {
    console.log('Approving USDC...');
  const hash = await walletClient.writeContract({
      address: usdc.address,
      abi: usdc.abi as any,
      functionName: 'approve',
      args: [margin.address, amount]
    });
    console.log('Approve tx hash:', hash);
  } else {
    console.log('Sufficient allowance, skip approve');
  }

  console.log('Depositing margin...');
  const depositHash = await walletClient.writeContract({
    address: margin.address,
    abi: margin.abi as any,
    functionName: 'deposit',
    args: [amount]
  });
  console.log('Deposit tx hash:', depositHash);

  const balance = (await publicClient.readContract({
    address: margin.address,
    abi: margin.abi as any,
    functionName: 'getTotalBalance',
    args: [account.address]
  })) as bigint;
  console.log('Total margin balance (USDC):', Number(balance) / 1e6);
}

main().catch(e => {
  console.error(e);
  process.exit(1);
});
