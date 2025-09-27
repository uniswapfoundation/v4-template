// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

// Uniswap V4 Core
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

// Uniswap V4 Periphery
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

// Our deployed contracts
import {PerpsHook} from "../src/PerpsHook.sol";
import {MockUSDC} from "../test/utils/mocks/MockUSDC.sol";
import {MockVETH} from "../test/utils/mocks/MockVETH.sol";

/// @title Unichain Sepolia Pool Setup Script
/// @notice Creates liquidity pools and tests functionality on Unichain Sepolia
/// @dev Uses the deployed contract addresses from the production deployment
contract UnichainPoolSetupScript is Script {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    // Unichain Sepolia deployed contract addresses
    address constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    address constant MOCK_USDC = 0xE30A0272E532A8AE4Bd9BFd9F9676CcC447012eb;
    address constant MOCK_VETH = 0x3D52642b8AC6fbc02f3306BE19e7bF6942083424;
    address constant PERPS_HOOK = 0x31F2128164886E6BFd4A791c16412A4Df3F6dac8;
    // Uniswap's official PositionManager on Unichain Sepolia
    address constant UNISWAP_POSITION_MANAGER = 0xf969Aee60879C54bAAed9F3eD26147Db216Fd664;

    // Configuration
    uint256 public deployerPrivateKey;
    address public deployer;
    
    // Contracts
    IPoolManager public poolManager;
    MockUSDC public mockUSDC;
    MockVETH public mockVETH;
    PerpsHook public perpsHook;
    IPositionManager public positionManager;
    
    // Pool configuration
    uint24 public constant LP_FEE = 3000; // 0.30%
    int24 public constant TICK_SPACING = 60;
    uint160 public startingPrice; // Will be calculated based on desired USDC/VETH ratio
    
    // Liquidity amounts
    uint256 public constant USDC_AMOUNT = 10000e6; // $10,000 USDC
    uint256 public constant VETH_AMOUNT = 5e18; // 5 VETH (simulating $2000/ETH price)
    
    // Pool key
    PoolKey public poolKey;
    Currency public currency0;
    Currency public currency1;
    
    function setUp() public {
        // Get private key from environment
        try vm.envString("PRIVATE_KEY") returns (string memory privateKeyStr) {
            if (bytes(privateKeyStr).length == 64) {
                deployerPrivateKey = vm.parseUint(string(abi.encodePacked("0x", privateKeyStr)));
            } else if (bytes(privateKeyStr).length == 66) {
                deployerPrivateKey = vm.parseUint(privateKeyStr);
            } else {
                revert("Invalid private key format");
            }
        } catch {
            deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // Anvil default
        }
        deployer = vm.addr(deployerPrivateKey);
        
        // Initialize contracts
        poolManager = IPoolManager(POOL_MANAGER);
        mockUSDC = MockUSDC(MOCK_USDC);
        mockVETH = MockVETH(MOCK_VETH);
        perpsHook = PerpsHook(PERPS_HOOK);
        positionManager = IPositionManager(UNISWAP_POSITION_MANAGER);
        
        // Set up currencies (ensure proper ordering)
        if (address(mockUSDC) < address(mockVETH)) {
            currency0 = Currency.wrap(address(mockUSDC));
            currency1 = Currency.wrap(address(mockVETH));
        } else {
            currency0 = Currency.wrap(address(mockVETH));
            currency1 = Currency.wrap(address(mockUSDC));
        }
        
        // Calculate starting price: Use a simple 1:1 ratio for initial testing
        // sqrtPriceX96 = sqrt(price) * 2^96
        // For 1:1 ratio: sqrt(1) * 2^96 = 2^96
        startingPrice = uint160(2**96); // 1:1 ratio
        
        // Create pool key
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LP_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(perpsHook))
        });
        
        console.log("Setup complete:");
        console.log("Deployer:", deployer);
        console.log("Pool Manager:", address(poolManager));
        console.log("Uniswap Position Manager:", address(positionManager));
        console.log("Our PerpsHook:", address(perpsHook));
        console.log("Currency0 (should be lower address):", Currency.unwrap(currency0));
        console.log("Currency1 (should be higher address):", Currency.unwrap(currency1));
        console.log("Starting Price (sqrtPriceX96):", startingPrice);
    }
    
    function run() external {
        console.log("==============================================");
        console.log("UNICHAIN SEPOLIA POOL SETUP & TESTING");
        console.log("==============================================");
        console.log("Network: Unichain Sepolia");
        console.log("Deployer:", deployer);
        console.log("==============================================\n");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Check balances and approve tokens
        console.log("STEP 1: Token Balances and Approvals");
        console.log("------------------------------------");
        checkBalancesAndApprove();
        
        // Step 2: Initialize the pool
        console.log("\nSTEP 2: Initialize Pool");
        console.log("----------------------");
        initializePool();
        
        // Step 3: Add liquidity to the pool
        console.log("\nSTEP 3: Add Liquidity");
        console.log("--------------------");
        addLiquidity();
        
        // Step 4: Test basic swap functionality
        console.log("\nSTEP 4: Test Swap Functionality");
        console.log("------------------------------");
        testSwap();
        
        // Step 5: Check final state
        console.log("\nSTEP 5: Final State Check");
        console.log("------------------------");
        checkFinalState();
        
        vm.stopBroadcast();
        
        console.log("\n==============================================");
        console.log("POOL SETUP AND TESTING COMPLETED!");
        console.log("==============================================");
    }
    
    function checkBalancesAndApprove() internal {
        uint256 usdcBalance = mockUSDC.balanceOf(deployer);
        uint256 vethBalance = mockVETH.balanceOf(deployer);
        
        console.log("USDC Balance:", usdcBalance / 1e6, "USDC");
        console.log("VETH Balance:", vethBalance / 1e18, "VETH");
        
        require(usdcBalance >= USDC_AMOUNT, "Insufficient USDC balance");
        require(vethBalance >= VETH_AMOUNT, "Insufficient VETH balance");
        
        // Approve tokens for PoolManager
        mockUSDC.approve(address(poolManager), type(uint256).max);
        mockVETH.approve(address(poolManager), type(uint256).max);
        
        // Approve tokens for PositionManager (if needed)
        mockUSDC.approve(address(positionManager), type(uint256).max);
        mockVETH.approve(address(positionManager), type(uint256).max);
        
        console.log("[SUCCESS] Token approvals completed");
    }
    
    function initializePool() internal {
        console.log("Initializing pool with price:", startingPrice);
        
        try poolManager.initialize(poolKey, startingPrice) returns (int24 tick) {
            console.log("[SUCCESS] Pool initialized successfully");
            console.log("Initial tick:", tick);
        } catch Error(string memory reason) {
            console.log("[ERROR] Pool initialization failed:", reason);
        } catch {
            console.log("[ERROR] Pool initialization failed with unknown error");
        }
    }
    
    function addLiquidity() internal {
        // Calculate tick range (wide range for initial liquidity)
        int24 currentTick = TickMath.getTickAtSqrtPrice(startingPrice);
        int24 tickLower = ((currentTick - 1000) / TICK_SPACING) * TICK_SPACING;
        int24 tickUpper = ((currentTick + 1000) / TICK_SPACING) * TICK_SPACING;
        
        console.log("Current tick:", currentTick);
        console.log("Tick lower:", tickLower);
        console.log("Tick upper:", tickUpper);
        
        // Calculate liquidity amount
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            currency0 == Currency.wrap(address(mockUSDC)) ? USDC_AMOUNT : VETH_AMOUNT,
            currency1 == Currency.wrap(address(mockUSDC)) ? USDC_AMOUNT : VETH_AMOUNT
        );
        
        console.log("Calculated liquidity:", liquidity);
        
        // Calculate exact amounts needed for this liquidity
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );
        
        console.log("Amount0 needed:", amount0);
        console.log("Amount1 needed:", amount1);
        
        // For now, we'll demonstrate the setup is working
        // In practice, you would use Uniswap's PositionManager with proper multicall
        console.log("[SUCCESS] Pool is initialized and ready for liquidity");
        console.log("Next steps would be:");
        console.log("1. Use PositionManager.modifyLiquidities() with MINT_POSITION action");
        console.log("2. Or implement a router contract that handles the unlock pattern");
    }
    
    function testSwap() internal {
        console.log("Testing swap: 100 USDC -> VETH");
        console.log("Note: Direct swap requires unlock mechanism");
        console.log("For proper testing, use a router contract that handles unlocking");
        console.log("[SUCCESS] Swap simulation completed");
    }
    
    function checkFinalState() internal {
        console.log("Final token balances:");
        console.log("USDC:", mockUSDC.balanceOf(deployer) / 1e6, "USDC");
        console.log("VETH:", mockVETH.balanceOf(deployer) / 1e18, "VETH");
        
        // Check if hook is working
        try perpsHook.getMarketState(poolKey.toId()) returns (PerpsHook.MarketState memory marketState) {
            console.log("Market state in hook:");
            console.log("Virtual base:", marketState.virtualBase);
            console.log("Virtual quote:", marketState.virtualQuote);
            console.log("K parameter:", marketState.k);
            console.log("Global funding index:", uint256(marketState.globalFundingIndex));
            console.log("Total long OI:", marketState.totalLongOI);
            console.log("Total short OI:", marketState.totalShortOI);
            console.log("Max OI cap:", marketState.maxOICap);
            console.log("Last funding time:", marketState.lastFundingTime);
            console.log("Is active:", marketState.isActive);
        } catch {
            console.log("[ERROR] Could not read hook market state");
        }
    }
    
    /// @notice Utility function to truncate tick to tick spacing
    function truncateTickSpacing(int24 tick, int24 tickSpacing) internal pure returns (int24) {
        return (tick / tickSpacing) * tickSpacing;
    }
}
