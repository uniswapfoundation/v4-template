import 'dotenv/config';
import { http, createPublicClient, defineChain } from 'viem';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';
import { calculateUsdcVethPoolId, getPoolInfo } from './poolUtils';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'http://localhost:8545';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);

async function main() {
  const poolIdArg = process.argv[2];
  const c = getContracts(CHAIN_ID);
  const chain = defineChain({ id: CHAIN_ID, name: 'UnichainSepolia', nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 }, rpcUrls: { default: { http: [RPC_URL] }, public: { http: [RPC_URL] } } });
  const client = createPublicClient({ transport: http(RPC_URL), chain });

  let poolId: `0x${string}`;
  if (poolIdArg) {
    poolId = poolIdArg as `0x${string}`;
    console.log("Using provided PoolId:", poolId);
  } else {
    // Calculate pool ID dynamically from contract addresses
    poolId = calculateUsdcVethPoolId(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);
    
    const poolInfo = getPoolInfo(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);
    console.log("📊 Pool Configuration:");
    console.log("  Currency0 (lower):", poolInfo.poolKey.currency0);
    console.log("  Currency1 (higher):", poolInfo.poolKey.currency1);
    console.log("  Fee:", poolInfo.poolKey.fee);
    console.log("  Tick Spacing:", poolInfo.poolKey.tickSpacing);
    console.log("  Hook:", poolInfo.poolKey.hooks);
    console.log("  Base Asset (VETH):", poolInfo.baseAsset);
    console.log("  Quote Asset (USDC):", poolInfo.quoteAsset);
    console.log("🆔 Calculated PoolId:", poolId);
  }

  try {
    const markPrice = await client.readContract({
      address: c.fundingOracle.address,
      abi: c.fundingOracle.abi as any,
      functionName: 'getMarkPrice',
      args: [poolId]
    });
    console.log('Mark price:', markPrice);
  } catch (e) {
    console.error('Failed to get mark price:', e);
  }
}

main().catch(e => { console.error(e); process.exit(1); });
