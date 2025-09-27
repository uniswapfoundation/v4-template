import { createPublicClient, createWalletClient, http, keccak256, toHex } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { unichainSepolia } from 'viem/chains';
import { externalContracts } from './contracts';

// Configuration
const PRIVATE_KEY = process.env.PRIVATE_KEY as `0x${string}`;
if (!PRIVATE_KEY) {
  throw new Error("PRIVATE_KEY environment variable is required");
}

const RPC_URL = "https://sepolia.unichain.org";
const CHAIN_ID = 1301; // Unichain Sepolia

// Setup clients
const account = privateKeyToAccount(PRIVATE_KEY.startsWith('0x') ? PRIVATE_KEY : `0x${PRIVATE_KEY}`);
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

// VETH-USDC Market configuration
const VETH_USDC_MARKET_ID = keccak256(toHex("VETH-USDC"));
const MOCK_POOL_ADDRESS = "0x1234567890123456789012345678901234567890"; // Mock pool address

async function addVethUsdcMarket() {
  console.log("🏪 Adding VETH-USDC Market to MarketManager");
  console.log("===========================================");
  console.log("Market Manager Address:", contracts.marketManager.address);
  console.log("VETH Address:", contracts.mockVETH.address);
  console.log("USDC Address:", contracts.mockUSDC.address);
  console.log("Market ID:", VETH_USDC_MARKET_ID);
  console.log("Deployer Address:", account.address);
  console.log("");

  try {
    // Step 1: Check if we're a key manager
    console.log("1. Checking Key Manager Status...");
    const isKeyManager = await publicClient.readContract({
      address: contracts.marketManager.address as `0x${string}`,
      abi: contracts.marketManager.abi,
      functionName: 'keyManagers',
      args: [account.address],
    });
    console.log(`   Key Manager Status: ${isKeyManager ? '✅ Authorized' : '❌ Not authorized'}`);

    if (!isKeyManager) {
      console.log("❌ Cannot add market - not authorized as key manager");
      return;
    }

    // Step 2: Check if market already exists
    console.log("\n2. Checking if VETH-USDC market already exists...");
    try {
      const existingMarket = await publicClient.readContract({
        address: contracts.marketManager.address as `0x${string}`,
        abi: contracts.marketManager.abi,
        functionName: 'getMarket',
        args: [VETH_USDC_MARKET_ID],
      });
      
      // Check if market has valid data (non-zero baseAsset address)
      if (existingMarket && existingMarket.baseAsset !== '0x0000000000000000000000000000000000000000') {
        console.log("   ✅ VETH-USDC market already exists:", existingMarket);
        return;
      } else {
        console.log("   Market exists but has zero data, will overwrite...");
      }
    } catch (error) {
      console.log("   Market does not exist, proceeding to add...");
    }

    // Step 3: Add VETH-USDC market
    console.log("\n3. Adding VETH-USDC Market...");
    
    const txHash = await walletClient.writeContract({
      address: contracts.marketManager.address as `0x${string}`,
      abi: contracts.marketManager.abi,
      functionName: 'addMarket',
      args: [
        VETH_USDC_MARKET_ID,
        contracts.mockVETH.address, // baseAsset (VETH)
        contracts.mockUSDC.address, // quoteAsset (USDC)
        MOCK_POOL_ADDRESS           // poolAddress (mock for now)
      ],
    });

    console.log("   Transaction Hash:", txHash);
    
    // Wait for confirmation
    const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
    console.log(`   Status: ${receipt.status === 'success' ? '✅ Success' : '❌ Failed'}`);
    console.log("   Block Number:", receipt.blockNumber);
    console.log("   Gas Used:", receipt.gasUsed);

    // Step 4: Verify market was added
    console.log("\n4. Verifying VETH-USDC Market Addition...");
    try {
      const market = await publicClient.readContract({
        address: contracts.marketManager.address as `0x${string}`,
        abi: contracts.marketManager.abi,
        functionName: 'getMarket',
        args: [VETH_USDC_MARKET_ID],
      });
      
      console.log("   ✅ VETH-USDC market successfully added!");
      console.log("   Base Asset (VETH):", market[0]);
      console.log("   Quote Asset (USDC):", market[1]);
      console.log("   Pool Address:", market[2]);
      console.log("   Is Active:", market[4]);
      
    } catch (error) {
      console.log("   ❌ Market verification failed:", error);
    }

  } catch (error) {
    console.error("❌ Error adding VETH-USDC market:", error);
  }
}

async function main() {
  console.log("🚀 VETH-USDC Market Addition Script");
  console.log("===================================");
  console.log("Network: Unichain Sepolia");
  console.log("RPC URL:", RPC_URL);
  console.log("");

  await addVethUsdcMarket();

  console.log("\n✅ VETH-USDC market addition completed!");
}

// Execute if called directly
if (require.main === module) {
  main().catch(console.error);
}
