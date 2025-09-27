import { createPublicClient, createWalletClient, http, parseEther, formatEther, encodeFunctionData, keccak256, toHex } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { unichainSepolia } from 'viem/chains';
import { externalContracts } from './contracts';

// Configuration
const PRIVATE_KEY = process.env.PRIVATE_KEY as `0x${string}`;
if (!PRIVATE_KEY) {
  throw new Error("PRIVATE_KEY environment variable is required");
}

// Ensure private key has 0x prefix
const formattedPrivateKey = PRIVATE_KEY.startsWith('0x') ? PRIVATE_KEY : `0x${PRIVATE_KEY}` as `0x${string}`;

const RPC_URL = "https://sepolia.unichain.org";
const CHAIN_ID = 1301; // Unichain Sepolia

// Setup clients
const account = privateKeyToAccount(formattedPrivateKey);
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

// Market configuration
const ETH_USDC_MARKET_ID = keccak256(toHex("ETH-USDC"));

async function testKeyManagerFunctionality() {
  console.log("🔑 Testing Key Manager Functionality");
  console.log("=====================================");
  console.log("Key Manager Address:", account.address);
  console.log("MarketManager Address:", contracts.marketManager.address);
  console.log("ETH-USDC Market ID:", ETH_USDC_MARKET_ID);
  console.log("");

  try {
    // Step 1: Check if we're already a key manager for MarketManager
    console.log("1. Checking Key Manager Status...");
    const isKeyManager = await publicClient.readContract({
      address: contracts.marketManager.address as `0x${string}`,
      abi: contracts.marketManager.abi,
      functionName: 'keyManagers',
      args: [account.address],
    });
    console.log(`   Key Manager Status: ${isKeyManager ? '✅ Authorized' : '❌ Not authorized'}`);

    // Step 2: Check if market already exists
    console.log("\n2. Checking Market Status...");
    try {
      const market = await publicClient.readContract({
        address: contracts.marketManager.address as `0x${string}`,
        abi: contracts.marketManager.abi,
        functionName: 'getMarket',
        args: [ETH_USDC_MARKET_ID],
      });
      console.log("   Market exists:", market);
    } catch (error) {
      console.log("   Market does not exist yet");
    }

    // Step 3: Add market as key manager
    if (isKeyManager) {
      console.log("\n3. Adding ETH-USDC Market as Key Manager...");
      
      const txHash = await walletClient.writeContract({
        address: contracts.marketManager.address as `0x${string}`,
        abi: contracts.marketManager.abi,
        functionName: 'addMarket',
        args: [
          ETH_USDC_MARKET_ID,
          contracts.mockVETH.address, // baseAsset (VETH)
          contracts.mockUSDC.address, // quoteAsset (USDC)
          "0x1234567890123456789012345678901234567890" // poolAddress (mock)
        ],
      });

      console.log("   Transaction Hash:", txHash);
      
      // Wait for confirmation
      const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
      console.log(`   Status: ${receipt.status === 'success' ? '✅ Success' : '❌ Failed'}`);
      console.log("   Block Number:", receipt.blockNumber);
      console.log("   Gas Used:", receipt.gasUsed);

      // Verify market was added
      console.log("\n4. Verifying Market Addition...");
      try {
        const market = await publicClient.readContract({
          address: contracts.marketManager.address as `0x${string}`,
          abi: contracts.marketManager.abi,
          functionName: 'getMarket',
          args: [ETH_USDC_MARKET_ID],
        });
        console.log("   ✅ Market successfully added:", market);
      } catch (error) {
        console.log("   ❌ Market verification failed:", error);
      }
    } else {
      console.log("\n❌ Cannot add market - not authorized as key manager");
      console.log("   Please ensure the deployment script properly set key manager permissions");
    }

  } catch (error) {
    console.error("❌ Error testing key manager functionality:", error);
  }
}

async function main() {
  console.log("🚀 Key Manager Test Script");
  console.log("==========================");
  console.log("Network: Unichain Sepolia");
  console.log("RPC URL:", RPC_URL);
  console.log("");

  await testKeyManagerFunctionality();

  console.log("\n✅ Key Manager test completed!");
}

// Execute if called directly
if (require.main === module) {
  main().catch(console.error);
}
