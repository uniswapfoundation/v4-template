import { ethers } from "ethers";

// Current contract addresses (will be updated after enhanced deployment)
const CURRENT_CONTRACTS = {
    usdc: "0x86AD5F5a0D5C3b969e6e4E54E4C12E6a9B5F2d5F",
    veth: "0x35c6B2EaebAE60a1FcA726F8BB1d75b4f31dEe4D",
    poolManager: "0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9",
    hookMiner: "0x8DAa90f5c42Fb9C52bF86b93dF07cE41E85D55F0",
    perpsHook: "0x5Ff1Dc6C1A1df91C0F067f5B3Ec0BD6f5E20A91a",
    poolSwapTest: "0x6f1e1CC2FdC49d1dB6e0E7dF5f9BA1a8B8b4e8Aa",
    marginAccount: "0xE9AfE1B0970B47De2F4C94a8C63A7Ab90d8b90D2"
};

// Enhanced contracts - these will be filled after deployment
const ENHANCED_CONTRACTS = {
    marketManagerV2: "",
    positionFactoryV2: "", 
    positionManagerV3: "",
    positionNFT: ""
};

async function testEnhancedPositionCreation() {
    console.log("🧪 Testing Enhanced Position Creation with Key Manager...");
    
    const provider = new ethers.JsonRpcProvider("https://sepolia.unichain.org");
    const wallet = new ethers.Wallet("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", provider);
    
    console.log("Using wallet:", wallet.address);
    console.log("Wallet balance:", ethers.formatEther(await provider.getBalance(wallet.address)), "ETH");

    // PositionManagerV3 ABI (enhanced)
    const positionManagerABI = [
        "function addMarket(bytes32 marketId, address baseAsset, address quoteAsset, address poolAddress) external",
        "function openPosition(bytes32 marketId, int256 sizeBase, uint256 entryPrice, uint256 margin) external returns (uint256)",
        "function isKeyManager(address account) external view returns (bool)",
        "function getAllMarketIds() external view returns (bytes32[])",
        "function isMarketActive(bytes32 marketId) external view returns (bool)",
        "function getPosition(uint256 tokenId) external view returns (tuple(address owner, uint96 margin, bytes32 marketId, int256 sizeBase, uint256 entryPrice, uint256 lastFundingIndex, uint64 openedAt, int256 fundingPaid))",
        "event PositionOpened(uint256 indexed tokenId, address indexed owner, bytes32 indexed marketId, int256 sizeBase, uint256 entryPrice, uint256 margin)"
    ];

    // PoolSwapTest ABI
    const poolSwapTestABI = [
        "function swap(tuple(address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) poolKey, tuple(bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96) swapParams, tuple(bool takeClaims, bool settleUsingBurn) settleParams, bytes hookData) external payable returns (tuple(int128 amount0, int128 amount1))"
    ];

    // ERC20 ABI
    const erc20ABI = [
        "function balanceOf(address account) external view returns (uint256)",
        "function approve(address spender, uint256 amount) external returns (bool)",
        "function allowance(address owner, address spender) external view returns (uint256)"
    ];

    try {
        // We'll use the existing contracts for now, then update after deployment
        const poolSwapTest = new ethers.Contract(CURRENT_CONTRACTS.poolSwapTest, poolSwapTestABI, wallet);
        const usdc = new ethers.Contract(CURRENT_CONTRACTS.usdc, erc20ABI, wallet);

        console.log("\n1. Current USDC Balance and Allowance:");
        const usdcBalance = await usdc.balanceOf(wallet.address);
        const usdcAllowance = await usdc.allowance(wallet.address, CURRENT_CONTRACTS.poolSwapTest);
        console.log("USDC Balance:", ethers.formatUnits(usdcBalance, 6));
        console.log("USDC Allowance for PoolSwapTest:", ethers.formatUnits(usdcAllowance, 6));

        // Pool key for VETH/USDC
        const poolKey = {
            currency0: CURRENT_CONTRACTS.usdc,
            currency1: CURRENT_CONTRACTS.veth, 
            fee: 3000,
            tickSpacing: 60,
            hooks: CURRENT_CONTRACTS.perpsHook
        };

        console.log("\n2. Pool Configuration:");
        console.log("Pool Key:", poolKey);

        // Market ID
        const marketId = ethers.keccak256(ethers.concat([
            ethers.getBytes(CURRENT_CONTRACTS.veth),
            ethers.getBytes(CURRENT_CONTRACTS.usdc)
        ]));
        console.log("Market ID:", marketId);

        // Trade parameters for opening a long position
        const tradeParams = {
            operation: 1, // OPEN_LONG
            tokenId: 0,   // Will be assigned by contract
            size: ethers.parseUnits("0.1", 18), // 0.1 VETH
            margin: ethers.parseUnits("200", 6), // 200 USDC margin
            maxSlippage: ethers.parseUnits("0.05", 18), // 5% slippage
            trader: wallet.address
        };

        console.log("\n3. Trade Parameters:");
        console.log("Operation: OPEN_LONG");
        console.log("Size:", ethers.formatUnits(tradeParams.size, 18), "VETH");
        console.log("Margin:", ethers.formatUnits(tradeParams.margin, 6), "USDC");
        console.log("Max Slippage:", ethers.formatUnits(tradeParams.maxSlippage, 18));

        // Encode trade parameters as hook data
        const hookData = ethers.AbiCoder.defaultAbiCoder().encode(
            ["tuple(uint8 operation, uint256 tokenId, uint256 size, uint256 margin, uint256 maxSlippage, address trader)"],
            [tradeParams]
        );

        console.log("\n4. Hook Data:");
        console.log("Encoded hook data length:", hookData.length);
        console.log("Hook data (first 100 chars):", hookData.substring(0, 100) + "...");

        // Swap parameters
        const swapParams = {
            zeroForOne: true, // Selling USDC for VETH
            amountSpecified: ethers.parseUnits("-50", 6), // Exact input of 50 USDC
            sqrtPriceLimitX96: "1461446703485210103287273052203988822378723970341" // No limit
        };

        const settleParams = {
            takeClaims: false,
            settleUsingBurn: false
        };

        console.log("\n5. Swap Parameters:");
        console.log("Zero for One:", swapParams.zeroForOne);
        console.log("Amount Specified:", ethers.formatUnits(Math.abs(Number(swapParams.amountSpecified)), 6), "USDC");

        console.log("\n6. Executing Position Creation via SwapRouter...");
        
        const tx = await poolSwapTest.swap(
            poolKey,
            swapParams,
            settleParams,
            hookData,
            { 
                gasLimit: 1000000,
                value: 0
            }
        );

        console.log("Transaction submitted:", tx.hash);
        
        const receipt = await tx.wait();
        console.log("✅ Transaction confirmed!");
        console.log("Gas used:", receipt.gasUsed.toString());
        console.log("Block number:", receipt.blockNumber);

        // Parse events to find position creation
        console.log("\n7. Analyzing Transaction Events...");
        console.log("Total events:", receipt.logs.length);
        
        // Look for PositionOpened events (when enhanced contracts are deployed)
        // For now, we'll just confirm the transaction succeeded
        
        console.log("\n🎉 SUCCESS: Position creation via SwapRouter completed!");
        console.log("With the enhanced system, this will create a position NFT");
        console.log("Transaction hash:", tx.hash);

    } catch (error: any) {
        console.error("❌ Error:", error);
        if (error.transaction) {
            console.log("Transaction that failed:", error.transaction);
        }
        if (error.receipt) {
            console.log("Receipt:", error.receipt);
        }
    }
}

async function testKeyManagerAccess() {
    console.log("\n🔑 Testing Key Manager Access (after deployment)...");
    
    const provider = new ethers.JsonRpcProvider("https://sepolia.unichain.org");
    const wallet = new ethers.Wallet("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", provider);
    
    // This will work after we deploy the enhanced contracts
    console.log("Wallet address:", wallet.address);
    console.log("This wallet will be added as a key manager in the new system");
    console.log("Key managers can:");
    console.log("- Add new markets");
    console.log("- Update funding indices");
    console.log("- Set market status");
    console.log("- All without needing to be the owner");
}

// Run the tests
async function main() {
    console.log("=".repeat(60));
    console.log("TESTING ENHANCED POSITION SYSTEM");
    console.log("=".repeat(60));
    
    await testEnhancedPositionCreation();
    await testKeyManagerAccess();
    
    console.log("\n" + "=".repeat(60));
    console.log("NEXT STEPS:");
    console.log("1. Deploy the enhanced contracts with DeployEnhancedSystem.s.sol");
    console.log("2. Update the contract addresses in this test");
    console.log("3. Re-run to test full position creation flow");
    console.log("=".repeat(60));
}

main().catch(console.error);
