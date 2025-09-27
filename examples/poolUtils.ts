import { encodeAbiParameters, keccak256 } from 'viem';

/**
 * Pool configuration for USDC/VETH market
 */
export const POOL_CONFIG = {
  fee: 3000, // 0.3% fee tier
  tickSpacing: 60, // Standard for 0.3% fee tier
  sqrtPriceX96: "79228162514264337593543950336" // 1:1 price ratio
} as const;

/**
 * Calculate PoolId from PoolKey (matches Solidity PoolIdLibrary.toId())
 * Returns keccak256 hash of abi.encode(poolKey)
 */
export function calculatePoolId(
  currency0: string, 
  currency1: string, 
  fee: number, 
  tickSpacing: number, 
  hooks: string
): `0x${string}` {
  const encoded = encodeAbiParameters(
    [
      { type: 'address', name: 'currency0' },
      { type: 'address', name: 'currency1' },
      { type: 'uint24', name: 'fee' },
      { type: 'int24', name: 'tickSpacing' },
      { type: 'address', name: 'hooks' }
    ],
    [
      currency0 as `0x${string}`,
      currency1 as `0x${string}`,
      fee,
      tickSpacing,
      hooks as `0x${string}`
    ]
  );
  
  return keccak256(encoded);
}

/**
 * Get the proper currency ordering (currency0 < currency1)
 */
export function getCurrencyOrdering(tokenA: string, tokenB: string): [string, string] {
  return tokenA.toLowerCase() < tokenB.toLowerCase() 
    ? [tokenA, tokenB] 
    : [tokenB, tokenA];
}

/**
 * Create a pool key for USDC/VETH with the given hook
 */
export function createPoolKey(usdcAddress: string, vethAddress: string, hookAddress: string) {
  const [currency0, currency1] = getCurrencyOrdering(usdcAddress, vethAddress);
  
  return {
    currency0,
    currency1,
    fee: POOL_CONFIG.fee,
    tickSpacing: POOL_CONFIG.tickSpacing,
    hooks: hookAddress
  };
}

/**
 * Calculate pool ID for USDC/VETH market
 */
export function calculateUsdcVethPoolId(usdcAddress: string, vethAddress: string, hookAddress: string): `0x${string}` {
  const poolKey = createPoolKey(usdcAddress, vethAddress, hookAddress);
  return calculatePoolId(
    poolKey.currency0,
    poolKey.currency1,
    poolKey.fee,
    poolKey.tickSpacing,
    poolKey.hooks
  );
}

/**
 * Get pool information for display
 */
export function getPoolInfo(usdcAddress: string, vethAddress: string, hookAddress: string) {
  const poolKey = createPoolKey(usdcAddress, vethAddress, hookAddress);
  const poolId = calculatePoolId(
    poolKey.currency0,
    poolKey.currency1,
    poolKey.fee,
    poolKey.tickSpacing,
    poolKey.hooks
  );

  return {
    poolKey,
    poolId,
    isUsdcCurrency0: poolKey.currency0.toLowerCase() === usdcAddress.toLowerCase(),
    baseAsset: poolKey.currency0.toLowerCase() === usdcAddress.toLowerCase() ? vethAddress : usdcAddress,
    quoteAsset: poolKey.currency0.toLowerCase() === usdcAddress.toLowerCase() ? usdcAddress : vethAddress
  };
}
