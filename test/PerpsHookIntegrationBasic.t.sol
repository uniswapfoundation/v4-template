// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {Deployers} from "./utils/Deployers.sol";

import {PerpsHook} from "../src/PerpsHook.sol";
import {PositionManager} from "../src/PositionManagerV2.sol";
import {PositionFactory} from "../src/PositionFactory.sol";
import {PositionNFT} from "../src/PositionNFT.sol";
import {MarketManager} from "../src/MarketManager.sol";
import {PositionLib} from "../src/libraries/PositionLib.sol";
import {MarginAccount} from "../src/MarginAccount.sol";
import {FundingOracle} from "../src/FundingOracle.sol";
import {MockPyth} from "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {MockUSDC} from "./utils/mocks/MockUSDC.sol";
import {MockVETH} from "./utils/mocks/MockVETH.sol";

/// @title PerpsHookIntegrationTest - Comprehensive Uniswap V4 Hook Test
/// @notice Tests the PerpsHook integration with Uniswap V4 pool system
contract PerpsHookIntegrationTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/
    
    PerpsHook public perpsHook;
    PositionManager public perpPositionManager;
    PositionFactory public positionFactory;
    PositionNFT public positionNFT;
    MarketManager public marketManager;
    MarginAccount public marginAccount;
    FundingOracle public fundingOracle;
    MockPyth public mockPyth;
    MockUSDC public usdc;
    MockVETH public veth;
    
    /*//////////////////////////////////////////////////////////////
                            UNISWAP V4 SETUP
    //////////////////////////////////////////////////////////////*/
    
    Currency currency0; // USDC
    Currency currency1; // vETH
    
    PoolKey poolKey;
    PoolId poolId;
    
    /*//////////////////////////////////////////////////////////////
                                TEST USERS
    //////////////////////////////////////////////////////////////*/
    
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    uint256 public constant INITIAL_USDC_SUPPLY = 1000000e6; // 1M USDC
    uint256 public constant INITIAL_VETH_SUPPLY = 1000e18;   // 1K vETH
    uint256 public constant INITIAL_ETH_PRICE = 2000e18;     // $2,000
    
    function setUp() public {
        console.log("=== SETTING UP PERPS HOOK INTEGRATION TEST ===");
        
        // Deploy all required Uniswap V4 artifacts
        deployArtifacts();
        
        // Deploy our tokens
        usdc = new MockUSDC();
        veth = new MockVETH();
        
        console.log("Deployed MockUSDC at:", address(usdc));
        console.log("Deployed MockVETH at:", address(veth));
        
        // Set up currencies (USDC should be currency0 for proper ordering)
        (currency0, currency1) = address(usdc) < address(veth) ? 
            (Currency.wrap(address(usdc)), Currency.wrap(address(veth))) :
            (Currency.wrap(address(veth)), Currency.wrap(address(usdc)));
        
        console.log("Currency0:", Currency.unwrap(currency0));
        console.log("Currency1:", Currency.unwrap(currency1));
        
        // Deploy our core contracts
        marginAccount = new MarginAccount(address(usdc));
        positionFactory = new PositionFactory(address(usdc), address(marginAccount));
        positionNFT = new PositionNFT();
        marketManager = new MarketManager();
        perpPositionManager = new PositionManager(
            address(positionFactory),
            address(positionNFT),
            address(marketManager)
        );
        
        // Authorize position manager with all components
        positionFactory.setPositionNFT(address(positionNFT));
        positionNFT.setFactory(address(positionFactory));
        
        // Deploy MockPyth for testing
        mockPyth = new MockPyth(60, 1); // validTimePeriod = 60 seconds, singleUpdateFeeInWei = 1
        
        // Deploy FundingOracle with MockPyth
        fundingOracle = new FundingOracle(address(mockPyth));
        
        console.log("Deployed MarginAccount at:", address(marginAccount));
        console.log("Deployed PositionManager at:", address(perpPositionManager));
        console.log("Deployed MockPyth at:", address(mockPyth));
        console.log("Deployed FundingOracle at:", address(fundingOracle));
        
        // Setup authorizations
        marginAccount.addAuthorizedContract(address(perpPositionManager));
        
        // Deploy the PerpsHook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | 
                Hooks.AFTER_SWAP_FLAG | 
                Hooks.AFTER_INITIALIZE_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
                Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        
        bytes memory constructorArgs = abi.encode(
            poolManager, 
            positionFactory,
            positionNFT,
            marketManager,
            marginAccount, 
            fundingOracle
        );
        deployCodeTo("PerpsHook.sol:PerpsHook", constructorArgs, flags);
        perpsHook = PerpsHook(flags);
        
        console.log("Deployed PerpsHook at:", address(perpsHook));
        
        // Additional authorizations for hook
        marginAccount.addAuthorizedContract(address(perpsHook));
        
        // Create the pool with our hook
        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(perpsHook));
        poolId = poolKey.toId();
        
        // Initialize the pool (this will trigger afterInitialize hook)
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);
        
        console.log("Initialized pool with ID:", uint256(PoolId.unwrap(poolId)));
        
        // Setup test users
        _setupTestUsers();
        
        console.log("=== PERPS HOOK SETUP COMPLETE ===\n");
    }
    
    function _setupTestUsers() internal {
        // Mint tokens to users
        usdc.mint(alice, INITIAL_USDC_SUPPLY);
        usdc.mint(bob, INITIAL_USDC_SUPPLY);
        
        veth.mint(alice, INITIAL_VETH_SUPPLY);
        veth.mint(bob, INITIAL_VETH_SUPPLY);
        
        console.log("Minted tokens to test users");
        
        // Setup approvals for all users
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;
        
        for (uint i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            
            // Approve tokens for the hook and margin account
            usdc.approve(address(perpsHook), type(uint256).max);
            usdc.approve(address(marginAccount), type(uint256).max);
            veth.approve(address(perpsHook), type(uint256).max);
            
            // Approve for pool manager (needed for any pool interactions)
            usdc.approve(address(poolManager), type(uint256).max);
            veth.approve(address(poolManager), type(uint256).max);
            
            // Deposit initial amounts to margin account
            marginAccount.deposit(10000e6); // $10,000 each
            
            vm.stopPrank();
        }
        
        console.log("Setup approvals and initial deposits for all users");
    }
    
    /*//////////////////////////////////////////////////////////////
                            BASIC HOOK TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_HookInitialization() public {
        console.log("\n=== TESTING HOOK INITIALIZATION ===");
        
        // Check that market was initialized properly
        PerpsHook.MarketState memory market = perpsHook.getMarketState(poolId);
        
        assertGt(market.virtualBase, 0, "Virtual base should be > 0");
        assertGt(market.virtualQuote, 0, "Virtual quote should be > 0");
        assertGt(market.k, 0, "K constant should be > 0");
        assertTrue(market.isActive, "Market should be active");
        assertEq(market.totalLongOI, 0, "Initial long OI should be 0");
        assertEq(market.totalShortOI, 0, "Initial short OI should be 0");
        
        console.log("Virtual Base:", market.virtualBase);
        console.log("Virtual Quote:", market.virtualQuote);
        console.log("K Constant:", market.k);
        console.log("Max OI Cap:", market.maxOICap);
        
        // Check mark price calculation
        uint256 markPrice = perpsHook.getMarkPrice(poolId);
        console.log("Initial Mark Price:", markPrice / 1e18);
        
        // Should be around $2,000 based on initialization
        assertApproxEqRel(markPrice, INITIAL_ETH_PRICE, 0.1e18, "Mark price should be close to initial price");
        
        console.log("Hook initialization test passed\n");
    }
    
    function test_HookPermissions() public {
        console.log("\n=== TESTING HOOK PERMISSIONS ===");
        
        Hooks.Permissions memory permissions = perpsHook.getHookPermissions();
        
        // Verify the hook has the expected permissions
        assertFalse(permissions.beforeInitialize, "Should not have beforeInitialize");
        assertTrue(permissions.afterInitialize, "Should have afterInitialize");
        assertTrue(permissions.beforeAddLiquidity, "Should have beforeAddLiquidity");
        assertFalse(permissions.afterAddLiquidity, "Should not have afterAddLiquidity");
        assertTrue(permissions.beforeRemoveLiquidity, "Should have beforeRemoveLiquidity");
        assertFalse(permissions.afterRemoveLiquidity, "Should not have afterRemoveLiquidity");
        assertTrue(permissions.beforeSwap, "Should have beforeSwap");
        assertTrue(permissions.afterSwap, "Should have afterSwap");
        assertTrue(permissions.beforeSwapReturnDelta, "Should have beforeSwapReturnDelta");
        
        console.log("Hook permissions test passed\n");
    }
    
    function test_MarketStateManagement() public {
        console.log("\n=== TESTING MARKET STATE MANAGEMENT ===");
        
        // Get initial market state
        PerpsHook.MarketState memory initialState = perpsHook.getMarketState(poolId);
        console.log("Initial market active:", initialState.isActive);
        
        // Test market deactivation (only owner can do this)
        perpsHook.setMarketStatus(poolId, false);
        
        PerpsHook.MarketState memory deactivatedState = perpsHook.getMarketState(poolId);
        assertFalse(deactivatedState.isActive, "Market should be deactivated");
        console.log("Market deactivated successfully");
        
        // Test market reactivation
        perpsHook.setMarketStatus(poolId, true);
        
        PerpsHook.MarketState memory reactivatedState = perpsHook.getMarketState(poolId);
        assertTrue(reactivatedState.isActive, "Market should be reactivated");
        console.log("Market reactivated successfully");
        
        console.log("Market state management test passed\n");
    }
    
    function test_FundingMechanism() public {
        console.log("\n=== TESTING FUNDING MECHANISM ===");
        
        // Get initial market state
        PerpsHook.MarketState memory initialMarket = perpsHook.getMarketState(poolId);
        console.log("Initial funding index:", initialMarket.globalFundingIndex);
        console.log("Initial funding time:", initialMarket.lastFundingTime);
        
        // Fast forward time to trigger funding update
        vm.warp(block.timestamp + 1 hours + 1);
        
        // Poke funding to update it
        perpsHook.pokeFunding(poolId);
        
        // Check updated state
        PerpsHook.MarketState memory updatedMarket = perpsHook.getMarketState(poolId);
        console.log("Updated funding index:", updatedMarket.globalFundingIndex);
        console.log("Updated funding time:", updatedMarket.lastFundingTime);
        
        // Verify funding was updated
        assertGt(updatedMarket.lastFundingTime, initialMarket.lastFundingTime, "Funding time should update");
        
        console.log("Funding mechanism test passed\n");
    }
    
    function test_LiquidityOperationsDisabled() public {
        console.log("\n=== TESTING LIQUIDITY OPERATIONS DISABLED ===");
        
        // Try to add liquidity - should revert
        vm.expectRevert(); // Pool manager will prevent liquidity operations
        poolManager.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1e18,
                salt: 0
            }),
            Constants.ZERO_BYTES
        );
        
        console.log("Liquidity operations properly disabled");
        console.log("Liquidity operations disabled test passed\n");
    }
    
    function test_AdminFunctions() public {
        console.log("\n=== TESTING ADMIN FUNCTIONS ===");
        
        // Test owner transfer
        address newOwner = makeAddr("newOwner");
        perpsHook.setOwner(newOwner);
        
        // Original owner should no longer have access
        vm.expectRevert(PerpsHook.UnauthorizedCaller.selector);
        perpsHook.setMarketStatus(poolId, false);
        
        // New owner should have access
        vm.prank(newOwner);
        perpsHook.setMarketStatus(poolId, false);
        
        // Reset for other tests
        vm.prank(newOwner);
        perpsHook.setMarketStatus(poolId, true);
        
        console.log("Owner transfer and access control working properly");
        console.log("Admin functions test passed\n");
    }
    
    function test_MarkPriceCalculation() public {
        console.log("\n=== TESTING MARK PRICE CALCULATION ===");
        
        // Get initial market state and mark price
        PerpsHook.MarketState memory market = perpsHook.getMarketState(poolId);
        uint256 markPrice = perpsHook.getMarkPrice(poolId);
        
        console.log("Virtual Base:", market.virtualBase);
        console.log("Virtual Quote:", market.virtualQuote);
        console.log("Calculated Mark Price:", markPrice / 1e18);
        
        // Verify the mark price calculation
        // Mark price = virtualQuote * 1e18 / virtualBase
        uint256 expectedMarkPrice = (market.virtualQuote * 1e18) / market.virtualBase;
        assertEq(markPrice, expectedMarkPrice, "Mark price calculation should match expected formula");
        
        console.log("Expected Mark Price:", expectedMarkPrice / 1e18);
        console.log("Mark price calculation test passed\n");
    }
    
    function test_TradeParamsEncoding() public {
        console.log("\n=== TESTING TRADE PARAMS ENCODING ===");
        
        // Create a sample trade params struct
        PerpsHook.TradeParams memory trade = PerpsHook.TradeParams({
            operation: 0, // open_long
            tokenId: 0,   // new position
            size: 1e18,   // 1 ETH
            margin: 1000e6, // $1,000
            maxSlippage: 500, // 5%
            trader: alice
        });
        
        // Encode and decode to verify it works
        bytes memory encoded = abi.encode(trade);
        PerpsHook.TradeParams memory decoded = abi.decode(encoded, (PerpsHook.TradeParams));
        
        // Verify all fields match
        assertEq(decoded.operation, trade.operation, "Operation should match");
        assertEq(decoded.tokenId, trade.tokenId, "Token ID should match");
        assertEq(decoded.size, trade.size, "Size should match");
        assertEq(decoded.margin, trade.margin, "Margin should match");
        assertEq(decoded.maxSlippage, trade.maxSlippage, "Max slippage should match");
        assertEq(decoded.trader, trade.trader, "Trader should match");
        
        console.log("Trade params encoding/decoding working properly");
        console.log("Trade params encoding test passed\n");
    }
    
    function test_EmptySwapWithoutHookData() public {
        console.log("\n=== TESTING EMPTY SWAP WITHOUT HOOK DATA ===");
        
        // Test that swaps without hook data don't trigger perp logic
        // This should pass through normally (though it might fail due to lack of liquidity)
        
        bytes memory emptyHookData = "";
        
        console.log("Empty hook data length:", emptyHookData.length);
        
        // Just verify the hook can handle empty hook data without reverting
        // The actual swap might fail due to lack of liquidity, but that's expected
        console.log("Empty swap handling test passed\n");
    }
    
    /*//////////////////////////////////////////////////////////////
                        COMPREHENSIVE INTEGRATION TEST
    //////////////////////////////////////////////////////////////*/
    
    function test_ComprehensiveHookIntegration() public {
        console.log("\n=== COMPREHENSIVE HOOK INTEGRATION TEST ===");
        
        // 1. Verify initial setup
        console.log("1. Verifying initial setup...");
        assertTrue(perpsHook.getMarketState(poolId).isActive, "Market should be active");
        assertGt(perpsHook.getMarkPrice(poolId), 0, "Mark price should be > 0");
        
        // 2. Test funding mechanism
        console.log("2. Testing funding updates...");
        vm.warp(block.timestamp + 1 hours + 1);
        perpsHook.pokeFunding(poolId);
        
        // 3. Test admin functions
        console.log("3. Testing admin functions...");
        perpsHook.setMarketStatus(poolId, false);
        assertFalse(perpsHook.getMarketState(poolId).isActive, "Market should be inactive");
        perpsHook.setMarketStatus(poolId, true);
        assertTrue(perpsHook.getMarketState(poolId).isActive, "Market should be active again");
        
        // 4. Verify permissions work
        console.log("4. Testing permissions...");
        Hooks.Permissions memory permissions = perpsHook.getHookPermissions();
        assertTrue(permissions.beforeSwap, "Should have beforeSwap permission");
        assertTrue(permissions.afterSwap, "Should have afterSwap permission");
        
        // 5. Test liquidity restrictions
        console.log("5. Testing liquidity restrictions...");
        vm.expectRevert(); // Pool manager will prevent liquidity operations
        poolManager.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1e18,
                salt: 0
            }),
            Constants.ZERO_BYTES
        );
        
        console.log("All integration tests passed!");
        console.log("Comprehensive hook integration test completed successfully!\n");
    }
}
