// Add initial liquidity to the VETH-USDC pool for trading
import { ethers } from "ethers";
import { getContracts, UNICHAIN_SEPOLIA } from "./contracts";

// Liquidity configuration
const LIQUIDITY_USDC_AMOUNT = "100000"; // 100,000 USDC (with 6 decimals)
const LIQUIDITY_VETH_AMOUNT = "50"; // 50 VETH (with 18 decimals)

// Price range for concentrated liquidity (around current price)
const TICK_LOWER = -60; // Lower price bound
const TICK_UPPER = 60;  // Upper price bound

export async function addLiquidityToPool(poolId: string) {
  console.log("💧 Adding Liquidity to VETH-USDC Pool");
  console.log("🆔 Pool ID:", poolId);
  
  // Get contract addresses
  const contracts = getContracts(UNICHAIN_SEPOLIA);
  
  // Setup provider and signer
  const provider = new ethers.JsonRpcProvider("https://sepolia.unichain.org");
  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("PRIVATE_KEY environment variable not set");
  }
  const signer = new ethers.Wallet(privateKey, provider);
  
  const deployerAddress = await signer.getAddress();
  console.log("📋 Using address:", deployerAddress);
  
  // Create contract instances
  const poolManager = new ethers.Contract(
    contracts.poolManager.address,
    contracts.poolManager.abi,
    signer
  );
  
  const uniswapPositionManager = new ethers.Contract(
    contracts.uniswapPositionManager.address,
    contracts.uniswapPositionManager.abi,
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
  
  // Determine currency order
  const isVETHCurrency0 = contracts.mockVETH.address.toLowerCase() < contracts.mockUSDC.address.toLowerCase();
  const currency0 = isVETHCurrency0 ? contracts.mockVETH.address : contracts.mockUSDC.address;
  const currency1 = isVETHCurrency0 ? contracts.mockUSDC.address : contracts.mockVETH.address;
  
  // Calculate amounts (respecting token decimals)
  const usdcAmount = ethers.parseUnits(LIQUIDITY_USDC_AMOUNT, 6);
  const vethAmount = ethers.parseUnits(LIQUIDITY_VETH_AMOUNT, 18);
  
  const amount0 = isVETHCurrency0 ? vethAmount : usdcAmount;
  const amount1 = isVETHCurrency0 ? usdcAmount : vethAmount;
  
  console.log("💰 Liquidity Amounts:");
  console.log(`  Amount0 (${isVETHCurrency0 ? 'VETH' : 'USDC'}):`, ethers.formatUnits(amount0, isVETHCurrency0 ? 18 : 6));
  console.log(`  Amount1 (${isVETHCurrency0 ? 'USDC' : 'VETH'}):`, ethers.formatUnits(amount1, isVETHCurrency0 ? 6 : 18));
  console.log("📊 Price Range:");
  console.log("  Tick Lower:", TICK_LOWER);
  console.log("  Tick Upper:", TICK_UPPER);
  
  try {
    // Check current balances
    const usdcBalance = await mockUSDC.balanceOf(deployerAddress);
    const vethBalance = await mockVETH.balanceOf(deployerAddress);
    
    console.log("💳 Current Balances:");
    console.log("  USDC:", ethers.formatUnits(usdcBalance, 6));
    console.log("  VETH:", ethers.formatUnits(vethBalance, 18));
    
    // Check if we have enough tokens
    if (usdcBalance < usdcAmount) {
      throw new Error(`Insufficient USDC balance. Need: ${ethers.formatUnits(usdcAmount, 6)}, Have: ${ethers.formatUnits(usdcBalance, 6)}`);
    }
    
    if (vethBalance < vethAmount) {
      throw new Error(`Insufficient VETH balance. Need: ${ethers.formatUnits(vethAmount, 18)}, Have: ${ethers.formatUnits(vethBalance, 18)}`);
    }
    
    // Approve tokens for Uniswap Position Manager
    console.log("🔓 Approving tokens...");
    
    const usdcApproveTx = await mockUSDC.approve(contracts.uniswapPositionManager.address, usdcAmount);
    await usdcApproveTx.wait();
    console.log("✅ USDC approved");
    
    const vethApproveTx = await mockVETH.approve(contracts.uniswapPositionManager.address, vethAmount);
    await vethApproveTx.wait();
    console.log("✅ VETH approved");
    
    // Add liquidity using Uniswap V4 Position Manager
    console.log("🔄 Adding liquidity...");
    
    const liquidityParams = {
      poolKey: {
        currency0,
        currency1,
        fee: 3000,
        tickSpacing: 60,
        hooks: contracts.perpsHook.address
      },
      tickLower: TICK_LOWER,
      tickUpper: TICK_UPPER,
      liquidityDelta: amount0, // Use amount0 as liquidity delta approximation
      salt: ethers.ZeroHash,
      hookData: "0x"
    };
    
    // Note: This is simplified - in practice you'd use the exact Uniswap V4 interface
    const liquidityTx = await uniswapPositionManager.modifyLiquidity(liquidityParams);
    
    console.log("⏳ Waiting for liquidity addition...");
    const receipt = await liquidityTx.wait();
    console.log("✅ Liquidity added! Transaction hash:", receipt.hash);
    
    // Get updated balances
    const newUsdcBalance = await mockUSDC.balanceOf(deployerAddress);
    const newVethBalance = await mockVETH.balanceOf(deployerAddress);
    
    console.log("💳 Updated Balances:");
    console.log("  USDC:", ethers.formatUnits(newUsdcBalance, 6));
    console.log("  VETH:", ethers.formatUnits(newVethBalance, 18));
    
    // Get pool liquidity
    const poolLiquidity = await poolManager.getLiquidity(poolId);
    console.log("🌊 Total Pool Liquidity:", poolLiquidity.toString());
    
    return {
      transactionHash: receipt.hash,
      blockNumber: receipt.blockNumber,
      amount0Used: amount0,
      amount1Used: amount1,
      poolLiquidity: poolLiquidity.toString()
    };
    
  } catch (error) {
    console.error("❌ Error adding liquidity:", error);
    throw error;
  }
}

// Execute if run directly
if (require.main === module) {
  const poolId = process.argv[2];
  if (!poolId) {
    console.error("❌ Please provide pool ID as argument");
    console.log("Usage: npm run add-liquidity <poolId>");
    process.exit(1);
  }
  
  addLiquidityToPool(poolId)
    .then((result) => {
      console.log("🎉 Liquidity addition completed successfully!");
      console.log("📊 Result:", result);
    })
    .catch((error) => {
      console.error("💥 Liquidity addition failed:", error);
      process.exit(1);
    });
}
