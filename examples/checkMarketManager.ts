import { createPublicClient, createWalletClient, http, keccak256, toHex } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { unichainSepolia } from 'viem/chains';
import { externalContracts } from './contracts';

// Configuration
const PRIVATE_KEY = `0x${process.env.PRIVATE_KEY}` as `0x${string}`;
const RPC_URL = "https://sepolia.unichain.org";
const CHAIN_ID = 1301;

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

const contracts = externalContracts[CHAIN_ID];
if (!contracts) {
  throw new Error(`No contracts found for chain ID ${CHAIN_ID}`);
}

const VETH_USDC_MARKET_ID = keccak256(toHex("VETH-USDC"));

async function main() {
  console.log("🔍 Checking MarketManager Status");
  console.log("================================");
  console.log("MarketManager Address:", contracts.marketManager.address);
  console.log("VETH-USDC Market ID:", VETH_USDC_MARKET_ID);
  console.log("VETH Address:", contracts.mockVETH.address);
  console.log("USDC Address:", contracts.mockUSDC.address);
  console.log("");

  try {
    // Check if we're a key manager
    const isKeyManager = await publicClient.readContract({
      address: contracts.marketManager.address as `0x${string}`,
      abi: contracts.marketManager.abi,
      functionName: 'keyManagers',
      args: [account.address],
    });
    console.log(`Key Manager Status: ${isKeyManager ? '✅ Authorized' : '❌ Not authorized'}`);

    // Try to get market data
    console.log("\n📊 Market Data:");
    try {
      const market = await publicClient.readContract({
        address: contracts.marketManager.address as `0x${string}`,
        abi: contracts.marketManager.abi,
        functionName: 'getMarket',
        args: [VETH_USDC_MARKET_ID],
      }) as any;

      console.log("Raw Market Data:", market);
      
      if (market && Array.isArray(market) && market.length >= 6) {
        console.log("   Base Asset (VETH):", market[0]);
        console.log("   Quote Asset (USDC):", market[1]);
        console.log("   Pool Address:", market[2]);
        console.log("   Last Funding Update:", market[3]);
        console.log("   Is Active:", market[4]);
        console.log("   Funding Index:", market[5]);
      } else {
        console.log("   Market data structure unexpected:", market);
      }
    } catch (error: any) {
      console.log("   ❌ Market not found or error:", error.message);
    }

    // Check if market is active
    try {
      const isActive = await publicClient.readContract({
        address: contracts.marketManager.address as `0x${string}`,
        abi: contracts.marketManager.abi,
        functionName: 'isMarketActive',
        args: [VETH_USDC_MARKET_ID],
      });
      console.log(`\n📈 Market Active Status: ${isActive ? 'Active' : 'Inactive'}`);
    } catch (error: any) {
      console.log("\n❌ Could not check market status:", error.message);
    }

    // If market doesn't exist or has invalid data, add it
    if (isKeyManager) {
      console.log("\n🔧 Adding/Updating VETH-USDC Market...");
      
      const txHash = await walletClient.writeContract({
        address: contracts.marketManager.address as `0x${string}`,
        abi: contracts.marketManager.abi,
        functionName: 'addMarket',
        args: [
          VETH_USDC_MARKET_ID,
          contracts.mockVETH.address, // baseAsset (VETH)
          contracts.mockUSDC.address, // quoteAsset (USDC) 
          "0x1234567890123456789012345678901234567890" // poolAddress (placeholder)
        ],
      });

      console.log("   Transaction Hash:", txHash);
      
      const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
      console.log(`   Status: ${receipt.status === 'success' ? '✅ Success' : '❌ Failed'}`);
      
      if (receipt.status === 'success') {
        // Verify the market was added correctly
        console.log("\n✅ Verifying Market Addition...");
        const verifyMarket = await publicClient.readContract({
          address: contracts.marketManager.address as `0x${string}`,
          abi: contracts.marketManager.abi,
          functionName: 'getMarket',
          args: [VETH_USDC_MARKET_ID],
        }) as any;
        
        console.log("   Verified Market Data:", verifyMarket);
        
        if (verifyMarket && Array.isArray(verifyMarket)) {
          console.log("   ✅ Base Asset (VETH):", verifyMarket[0]);
          console.log("   ✅ Quote Asset (USDC):", verifyMarket[1]);
          console.log("   ✅ Pool Address:", verifyMarket[2]);
          console.log("   ✅ Is Active:", verifyMarket[4]);
        }
      }
    }

  } catch (error) {
    console.error("❌ Error:", error);
  }
}

main().catch(console.error);
