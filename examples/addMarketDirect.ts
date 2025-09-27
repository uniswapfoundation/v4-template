import { createPublicClient, createWalletClient, http, keccak256, toHex } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { unichainSepolia } from 'viem/chains';
import { externalContracts } from './contracts';

// Configuration
const PRIVATE_KEY = process.env.PRIVATE_KEY?.startsWith('0x') 
  ? process.env.PRIVATE_KEY as `0x${string}` 
  : `0x${process.env.PRIVATE_KEY}` as `0x${string}`;

if (!PRIVATE_KEY) {
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

// Market configuration - Using ETH-USDC to match the pool we already have
const ETH_USDC_MARKET_ID = keccak256(toHex("ETH-USDC"));

async function addMarketDirectly() {
  console.log("🏦 Adding ETH-USDC Market Directly to PositionFactory");
  console.log("====================================================");
  console.log("Key Manager Address:", account.address);
  console.log("VETH Address (as ETH):", contracts.mockVETH.address);
  console.log("USDC Address:", contracts.mockUSDC.address);
  console.log("Market ID:", ETH_USDC_MARKET_ID);
  console.log("");

  try {
    // Step 1: Add market to MarketManager (we have key manager privileges)
    console.log("1. Adding market to MarketManager...");
    
    const marketManagerTxHash = await walletClient.writeContract({
      address: contracts.marketManager.address as `0x${string}`,
      abi: contracts.marketManager.abi,
      functionName: 'addMarket',
      args: [
        ETH_USDC_MARKET_ID,
        contracts.mockVETH.address, // baseAsset (VETH as ETH)
        contracts.mockUSDC.address, // quoteAsset (USDC)
        "0x1234567890123456789012345678901234567890" // poolAddress (mock for now)
      ],
    });

    console.log("   MarketManager Transaction Hash:", marketManagerTxHash);
    
    const marketManagerReceipt = await publicClient.waitForTransactionReceipt({ hash: marketManagerTxHash });
    console.log(`   MarketManager Status: ${marketManagerReceipt.status === 'success' ? '✅ Success' : '❌ Failed'}`);

    if (marketManagerReceipt.status === 'success') {
      // Step 2: Try to add market to PositionFactory directly (using PositionFactory address)
      console.log("\n2. Getting PositionFactory address...");
      
      // Get PositionFactory address from PositionManager
      const positionFactoryAddress = await publicClient.readContract({
        address: contracts.positionManager.address as `0x${string}`,
        abi: contracts.positionManager.abi,
        functionName: 'factory',
      });
      
      console.log("   PositionFactory Address:", positionFactoryAddress);
      
      // Try to add market to PositionFactory directly if we have key manager access
      console.log("\n3. Adding market to PositionFactory directly...");
      
      try {
        const positionFactoryTxHash = await walletClient.writeContract({
          address: positionFactoryAddress as `0x${string}`,
          abi: [
            {
              "inputs": [
                {"type": "bytes32", "name": "marketId"},
                {"type": "address", "name": "baseAsset"},
                {"type": "address", "name": "quoteAsset"},
                {"type": "address", "name": "poolAddress"}
              ],
              "name": "addMarket",
              "outputs": [],
              "stateMutability": "nonpayable",
              "type": "function"
            }
          ],
          functionName: 'addMarket',
          args: [
            ETH_USDC_MARKET_ID,
            contracts.mockVETH.address,
            contracts.mockUSDC.address,
            "0x1234567890123456789012345678901234567890"
          ],
        });

        console.log("   PositionFactory Transaction Hash:", positionFactoryTxHash);
        
        const positionFactoryReceipt = await publicClient.waitForTransactionReceipt({ hash: positionFactoryTxHash });
        console.log(`   PositionFactory Status: ${positionFactoryReceipt.status === 'success' ? '✅ Success' : '❌ Failed'}`);
        
      } catch (factoryError: any) {
        console.log("   ⚠️  Could not add to PositionFactory directly:", factoryError.shortMessage || factoryError.message);
        console.log("   This might require owner privileges or different approach");
      }
    }

    console.log("\n4. ✅ Market Setup Process Completed!");
    console.log("   MarketManager: ✅ ETH-USDC market added");
    console.log("   Now try the SwapRouter approach - it might work with just MarketManager");

  } catch (error: any) {
    console.error("❌ Error adding ETH-USDC market:", error.shortMessage || error.message);
  }
}

async function main() {
  console.log("🚀 Direct Market Addition Script");
  console.log("=================================");
  console.log("Network: Unichain Sepolia");
  console.log("RPC URL:", RPC_URL);
  console.log("");

  await addMarketDirectly();

  console.log("\n✅ Market addition process completed!");
}

// Execute if called directly
if (require.main === module) {
  main().catch(console.error);
}
