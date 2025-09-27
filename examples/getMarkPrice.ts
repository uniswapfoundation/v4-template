import 'dotenv/config';
import { http, createPublicClient, defineChain, keccak256, encodeAbiParameters, parseAbiParameters } from 'viem';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'http://localhost:8545';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);

/**
 * Calculate PoolId from PoolKey (matches Solidity PoolIdLibrary.toId())
 * Returns keccak256 hash of abi.encode(poolKey)
 */
function calculatePoolId(currency0: string, currency1: string, fee: number, tickSpacing: number, hooks: string): `0x${string}` {
  // ABI encode the pool key struct (matches Solidity struct layout)
  const encoded = encodeAbiParameters(
    parseAbiParameters("address, address, uint24, int24, address"),
    [
      currency0 as `0x${string}`,
      currency1 as `0x${string}`,
      fee,
      tickSpacing,
      hooks as `0x${string}`
    ]
  );
  
  // Return keccak256 hash
  return keccak256(encoded);
}

async function main() {
  const poolIdArg = process.argv[2];
  const c = getContracts(CHAIN_ID);
  const chain = defineChain({ id: CHAIN_ID, name: 'UnichainSepolia', nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 }, rpcUrls: { default: { http: [RPC_URL] }, public: { http: [RPC_URL] } } });
  const client = createPublicClient({ transport: http(RPC_URL), chain });

  let poolId: `0x${string}`;
  if (poolIdArg) {
    poolId = poolIdArg as `0x${string}`;
  } else {
    const fee = 3000;
    const tick = 60;
    const [currency0, currency1] = c.mockUSDC.address.toLowerCase() < c.mockVETH.address.toLowerCase()
      ? [c.mockUSDC.address, c.mockVETH.address]
      : [c.mockVETH.address, c.mockUSDC.address];
    poolId = calculatePoolId(currency0, currency1, fee, tick, c.perpsHook.address);
  }

  console.log("PoolId calculated from USDC/VETH pool configuration:", poolId);

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
