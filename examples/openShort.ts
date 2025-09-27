import 'dotenv/config';
import { http, createWalletClient, createPublicClient, parseUnits, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'http://localhost:8545';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing');

async function main() {
  const account = privateKeyToAccount(PK as `0x${string}`);
  const chain = defineChain({ id: CHAIN_ID, name: 'UnichainSepolia', nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 }, rpcUrls: { default: { http: [RPC_URL] }, public: { http: [RPC_URL] } } });
  const transport = http(RPC_URL);
  const publicClient = createPublicClient({ transport, chain });
  const walletClient = createWalletClient({ account, transport, chain });
  const c = getContracts(CHAIN_ID);

  const fee = 3000;
  const tickSpacing = 60;
  const hooks = c.perpsHook.address;
  const [currency0, currency1] = c.mockUSDC.address.toLowerCase() < c.mockVETH.address.toLowerCase()
    ? [c.mockUSDC.address, c.mockVETH.address]
    : [c.mockVETH.address, c.mockUSDC.address];

  const marginAmount = parseUnits(process.argv[2] || '500', 6); // default 500 USDC
  const leverage = parseUnits('3', 18); // 3x
  const slippageBps = 150n; // 1.5%
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 300);

  console.log('Opening SHORT position');

  const allowance = (await publicClient.readContract({
    address: c.mockUSDC.address,
    abi: c.mockUSDC.abi as any,
    functionName: 'allowance',
    args: [account.address, c.perpsRouter.address]
  })) as bigint;
  if (allowance < marginAmount) {
    console.log('Approving USDC for PerpsRouter...');
    await walletClient.writeContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'approve',
      args: [c.perpsRouter.address, marginAmount]
    });
  }

  const params = {
    poolKey: [currency0, currency1, fee, tickSpacing, hooks] as const,
    isLong: false,
    marginAmount,
    leverage,
    slippageBps,
    deadline
  } as const;

  const txHash = await walletClient.writeContract({
    address: c.perpsRouter.address,
    abi: c.perpsRouter.abi as any,
    functionName: 'openPosition',
    args: [params]
  });
  console.log('openPosition (short) tx:', txHash);
}

main().catch(e => { console.error(e); process.exit(1); });
