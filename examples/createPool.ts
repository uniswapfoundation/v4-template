// Create and initialize a new VETH-USDC liquidity pool with PerpsHook integration
import { ethers } from "ethers";
import { getContracts, UNICHAIN_SEPOLIA } from "./contracts";

// Pool configuration constants
const VETH_USDC_FEE = 3000; // 0.3% fee
const TICK_SPACING = 60; // Standard tick spacing for 0.3% fee tier
const INITIAL_SQRT_PRICE_X96 = "79228162514264337593543950336"; // 1:1 price ratio

// Helper function to encode pool key for Uniswap V4
function encodePoolKey(currency0: string, currency1: string, fee: number, tickSpacing: number, hooks: string) {
  return {
    currency0: currency0.toLowerCase() < currency1.toLowerCase() ? currency0 : currency1,
    currency1: currency0.toLowerCase() < currency1.toLowerCase() ? currency1 : currency0,
    fee,
    tickSpacing,
    hooks
  };
}

export async function createVETHUSDCPool() {
  console.log("🚀 Creating VETH-USDC Pool with PerpsHook Integration");
  
  // Get contract addresses
  const contracts = getContracts(UNICHAIN_SEPOLIA);
  
  // Setup provider and signer
  const provider = new ethers.JsonRpcProvider("https://sepolia.unichain.org");
  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("PRIVATE_KEY environment variable not set");
  }
  const signer = new ethers.Wallet(privateKey, provider);
  
  console.log("📋 Using deployer address:", await signer.getAddress());
  
  // Create contract instances
  const poolManager = new ethers.Contract(
    contracts.poolManager.address,
    contracts.poolManager.abi,
    signer
  );
  
  const mockUSDC = new ethers.Contract(
    contracts.mockUSDC.address,
    contracts.mockUSDC.abi,
    signer
  );
  
  const mockVETH = new ethers.Contract(
    contracts.mockVETH.address,
    contracts.mockVETH.abi,
    signer
  );
  
  // Determine currency order (lower address = currency0)
  const isVETHCurrency0 = contracts.mockVETH.address.toLowerCase() < contracts.mockUSDC.address.toLowerCase();
  const currency0 = isVETHCurrency0 ? contracts.mockVETH.address : contracts.mockUSDC.address;
  const currency1 = isVETHCurrency0 ? contracts.mockUSDC.address : contracts.mockVETH.address;
  
  console.log("💱 Pool Configuration:");
  console.log(`  Currency0 (${isVETHCurrency0 ? 'VETH' : 'USDC'}):`, currency0);
  console.log(`  Currency1 (${isVETHCurrency0 ? 'USDC' : 'VETH'}):`, currency1);
  console.log("  Fee:", VETH_USDC_FEE, "bps (0.3%)");
  console.log("  Tick Spacing:", TICK_SPACING);
  console.log("  Hook:", contracts.perpsHook.address);
  
  // Encode pool key
  const poolKey = encodePoolKey(
    currency0,
    currency1,
    VETH_USDC_FEE,
    TICK_SPACING,
    contracts.perpsHook.address
  );
  
  try {
    // Initialize the pool
    console.log("🔄 Initializing pool...");
    const initTx = await poolManager.initialize(
      poolKey,
      INITIAL_SQRT_PRICE_X96,
      "0x" // Empty hook data
    );
    
    console.log("⏳ Waiting for pool initialization...");
    const receipt = await initTx.wait();
    console.log("✅ Pool initialized! Transaction hash:", receipt.hash);
    
    // Calculate pool ID
    const poolId = ethers.keccak256(
      ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(address,address,uint24,int24,address)"],
        [[currency0, currency1, VETH_USDC_FEE, TICK_SPACING, contracts.perpsHook.address]]
      )
    );
    
    console.log("🆔 Pool ID:", poolId);
    
    // Check pool state
    const slot0 = await poolManager.getSlot0(poolId);
    console.log("📊 Pool State:");
    console.log("  Current sqrt price:", slot0.sqrtPriceX96.toString());
    console.log("  Current tick:", slot0.tick.toString());
    console.log("  Protocol fee:", slot0.protocolFee.toString());
    
    // Get current token balances
    const deployerAddress = await signer.getAddress();
    const usdcBalance = await mockUSDC.balanceOf(deployerAddress);
    const vethBalance = await mockVETH.balanceOf(deployerAddress);
    
    console.log("💰 Current Token Balances:");
    console.log("  USDC:", ethers.formatUnits(usdcBalance, 6));
    console.log("  VETH:", ethers.formatUnits(vethBalance, 18));
    
    return {
      poolId,
      poolKey,
      currency0,
      currency1,
      transactionHash: receipt.hash,
      blockNumber: receipt.blockNumber
    };
    
  } catch (error) {
    console.error("❌ Error creating pool:", error);
    throw error;
  }
}

// Execute if run directly
if (require.main === module) {
  createVETHUSDCPool()
    .then((result) => {
      console.log("🎉 Pool creation completed successfully!");
      console.log("📊 Result:", result);
    })
    .catch((error) => {
      console.error("💥 Pool creation failed:", error);
      process.exit(1);
    });
}
