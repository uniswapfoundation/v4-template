import { createPublicClient, createWalletClient, http, parseEther, formatEther, encodeAbiParameters, keccak256, toHex } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { unichainSepolia } from 'viem/chains';
import { externalContracts } from './contracts';

// Configuration
const PRIVATE_KEY = `0x${process.env.PRIVATE_KEY}` as `0x${string}`;
if (!PRIVATE_KEY || PRIVATE_KEY === '0x') {
  throw new Error("PRIVATE_KEY environment variable is required");
}

const RPC_URL = "https://sepolia.unichain.org";
const CHAIN_ID = 1301; // Unichain Sepolia

// Setup clients
const account = privateKeyToAccount(PRIVATE_KEY);
const publicClient = createPublicClient({
  chain: unichainSepolia,
  transport: http(RPC_URL),
});

const walletClient = createWalletClient({
  account,
  chain: unichainSepolia,
  transport: http(RPC_URL),
});

// Contract instances
const contracts = externalContracts[CHAIN_ID];
if (!contracts) {
  throw new Error(`No contracts found for chain ID ${CHAIN_ID}`);
}

// Pool configuration
const fee = 3000; // 0.3% fee tier
const tickSpacing = 60; // Standard for 0.3% fee tier
const sqrtPriceX96 = "79228162514264337593543950336"; // 1:1 price ratio

// PoolKey structure for VETH-USDC
const poolKey = {
  currency0: contracts.mockUSDC.address < contracts.mockVETH.address ? contracts.mockUSDC.address : contracts.mockVETH.address,
  currency1: contracts.mockUSDC.address < contracts.mockVETH.address ? contracts.mockVETH.address : contracts.mockUSDC.address,
  fee: fee,
  tickSpacing: tickSpacing,
  hooks: contracts.perpsHook.address
};

console.log("📝 Pool Configuration:");
console.log("Currency0 (token0):", poolKey.currency0);
console.log("Currency1 (token1):", poolKey.currency1);
console.log("Fee:", poolKey.fee);
console.log("Tick Spacing:", poolKey.tickSpacing);
console.log("Hooks:", poolKey.hooks);

// Calculate PoolId
function calculatePoolId(poolKey: any): `0x${string}` {
  const encoded = encodeAbiParameters(
    [
      { type: 'address', name: 'currency0' },
      { type: 'address', name: 'currency1' },
      { type: 'uint24', name: 'fee' },
      { type: 'int24', name: 'tickSpacing' },
      { type: 'address', name: 'hooks' }
    ],
    [poolKey.currency0, poolKey.currency1, poolKey.fee, poolKey.tickSpacing, poolKey.hooks]
  );
  return keccak256(encoded);
}

async function createPool() {
  console.log("🏊‍♂️ Creating VETH-USDC Pool");
  console.log("=============================");
  console.log("Account:", account.address);
  console.log("");

  try {
    // Calculate expected PoolId
    const expectedPoolId = calculatePoolId(poolKey);
    console.log("Expected PoolId:", expectedPoolId);
    console.log("");

    // Step 1: Initialize the pool
    console.log("1. Initializing Pool...");
    
    const initTxHash = await walletClient.writeContract({
      address: contracts.poolManager.address as `0x${string}`,
      abi: contracts.poolManager.abi,
      functionName: 'initialize',
      args: [poolKey, BigInt(sqrtPriceX96)],
    });

    console.log("   Transaction Hash:", initTxHash);
    
    // Wait for confirmation
    const receipt = await publicClient.waitForTransactionReceipt({ hash: initTxHash });
    console.log(`   Status: ${receipt.status === 'success' ? '✅ Success' : '❌ Failed'}`);
    console.log("   Block Number:", receipt.blockNumber);
    console.log("   Gas Used:", receipt.gasUsed);

    if (receipt.status === 'success') {
      console.log("");
      console.log("✅ Pool Created Successfully!");
      console.log("Pool Details:");
      console.log("- PoolId:", expectedPoolId);
      console.log("- Currency0:", poolKey.currency0);
      console.log("- Currency1:", poolKey.currency1);
      console.log("- Fee Tier:", poolKey.fee);
      console.log("- Hook Address:", poolKey.hooks);
      console.log("");
      console.log("🎯 Next Steps:");
      console.log("1. Use this PoolId to add the market to MarketManager");
      console.log("2. Add the market to PositionFactory");
      console.log("3. Test position opening with SwapRouter");
      
      return {
        poolId: expectedPoolId,
        poolKey: poolKey,
        transactionHash: initTxHash
      };
    } else {
      throw new Error("Pool initialization failed");
    }

  } catch (error) {
    console.error("❌ Error creating pool:", error);
    
    // Check if pool already exists
    console.log("\n🔍 Checking if pool already exists...");
    try {
      const expectedPoolId = calculatePoolId(poolKey);
      
      // Try to get pool slot0 to see if it exists
      const slot0 = await publicClient.readContract({
        address: contracts.poolManager.address as `0x${string}`,
        abi: contracts.poolManager.abi,
        functionName: 'getSlot0',
        args: [expectedPoolId],
      });
      
      console.log("✅ Pool already exists!");
      console.log("- PoolId:", expectedPoolId);
      console.log("- Slot0:", slot0);
      
      return {
        poolId: expectedPoolId,
        poolKey: poolKey,
        existed: true
      };
      
    } catch (checkError) {
      console.log("❌ Pool does not exist, original error was:", error);
      throw error;
    }
  }
}

async function main() {
  console.log("🚀 Pool Creation Script");
  console.log("=======================");
  console.log("Network: Unichain Sepolia");
  console.log("RPC URL:", RPC_URL);
  console.log("");

  const result = await createPool();
  
  console.log("\n✅ Script completed!");
  console.log("Result:", result);
}

// Execute if called directly
if (require.main === module) {
  main().catch(console.error);
}

export { createPool, calculatePoolId, poolKey };
