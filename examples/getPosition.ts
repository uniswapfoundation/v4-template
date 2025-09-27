import 'dotenv/config';
import { http, createPublicClient, defineChain } from 'viem';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'http://localhost:8545';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);

async function main() {
  const tokenIdArg = process.argv[2];
  if (!tokenIdArg) throw new Error('Usage: bun run examples/getPosition.ts <tokenId>');
  const tokenId = BigInt(tokenIdArg);
  const chain = defineChain({ id: CHAIN_ID, name: 'UnichainSepolia', nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 }, rpcUrls: { default: { http: [RPC_URL] }, public: { http: [RPC_URL] } } });
  const publicClient = createPublicClient({ transport: http(RPC_URL), chain });
  const c = getContracts(CHAIN_ID);

  const position = await publicClient.readContract({
    address: c.positionManager.address,
    abi: c.positionManager.abi as any,
    functionName: 'getPosition',
    args: [tokenId]
  });

  console.log('Position:', position);

  // Optionally fetch PnL via router helper if exposed
  try {
    const withPnl = await publicClient.readContract({
      address: c.perpsRouter.address,
      abi: c.perpsRouter.abi as any,
      functionName: 'getPositionWithPnL',
      args: [tokenId]
    });
    console.log('Position with PnL tuple:', withPnl);
  } catch {
    console.log('getPositionWithPnL not accessible or reverted');
  }
}

main().catch(e => { console.error(e); process.exit(1); });
