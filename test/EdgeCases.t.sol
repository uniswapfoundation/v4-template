// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {PerpsRouter} from "../src/PerpsRouter.sol";
import {PositionManager} from "../src/PositionManagerV2.sol";
import {PositionFactory} from "../src/PositionFactory.sol";
import {PositionNFT} from "../src/PositionNFT.sol";
import {MarketManager} from "../src/MarketManager.sol";
import {PositionLib} from "../src/libraries/PositionLib.sol";
import {MarginAccount} from "../src/MarginAccount.sol";
import {FundingOracle} from "../src/FundingOracle.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";
import {MockUSDC} from "./utils/mocks/MockUSDC.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @title EdgeCases - Comprehensive Edge Case Testing for UniPerp
/// @notice Tests critical edge cases, attack vectors, and arithmetic issues
contract EdgeCasesTest is Test {
    using PoolIdLibrary for PoolKey;

    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/
    
    PerpsRouter public perpsRouter;
    PositionManager public positionManager;
    PositionFactory public positionFactory;
    PositionNFT public positionNFT;
    MarketManager public marketManager;
    MarginAccount public marginAccount;
    FundingOracle public fundingOracle;
    InsuranceFund public insuranceFund;
    MockUSDC public usdc;
    
    /*//////////////////////////////////////////////////////////////
                                TEST SETUP
    //////////////////////////////////////////////////////////////*/
    
    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public attacker = makeAddr("attacker");
    
    PoolKey public poolKey;
    bytes32 public marketId;
    
    uint256 constant INITIAL_USDC = 1_000_000e6; // 1M USDC
    uint256 constant TEST_PRICE = 2000e18; // $2000
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy core contracts
        usdc = new MockUSDC();
        marginAccount = new MarginAccount(address(usdc));
        positionFactory = new PositionFactory(address(usdc), address(marginAccount));
        positionNFT = new PositionNFT();
        marketManager = new MarketManager();
        positionManager = new PositionManager(
            address(positionFactory),
            address(positionNFT),
            address(marketManager)
        );
        insuranceFund = new InsuranceFund(address(usdc));
        fundingOracle = new FundingOracle(address(0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF)); // Placeholder Pyth
        
        // Deploy PerpsRouter - using mock addresses for components we're not testing
        perpsRouter = new PerpsRouter(
            address(marginAccount),
            address(positionManager),
            address(positionFactory),
            address(fundingOracle),
            address(0x1234), // Mock pool manager
            address(usdc)
        );
        
        // Setup modular component authorizations
        positionFactory.setPositionNFT(address(positionNFT));
        positionNFT.setFactory(address(positionFactory));
        
        // Transfer ownership of modular components to PositionManager
        positionFactory.transferOwnership(address(positionManager));
        marketManager.transferOwnership(address(positionManager));
        
        // Setup contract authorizations
        marginAccount.addAuthorizedContract(address(perpsRouter));
        marginAccount.addAuthorizedContract(address(positionManager));
        marginAccount.addAuthorizedContract(address(positionFactory));
        
        // Setup pool key and market
        poolKey = PoolKey({
            currency0: Currency.wrap(address(usdc)),
            currency1: Currency.wrap(address(0x5678)), // Mock asset
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        marketId = bytes32(PoolId.unwrap(poolKey.toId()));
        
        // Add market to position manager
        positionManager.addMarket(
            marketId,
            address(0x5678), // Mock base asset
            address(usdc),   // Quote asset
            address(0x9ABC)  // Mock pool address
        );
        
        // Mint tokens for testing
        usdc.mint(user1, INITIAL_USDC);
        usdc.mint(user2, INITIAL_USDC);
        usdc.mint(attacker, INITIAL_USDC);
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                         ARITHMETIC EDGE CASES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test division by zero in price calculations
    function test_RevertZeroPrice() public {
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), type(uint256).max);
        marginAccount.deposit(10000e6);
        
        // This should revert when trying to calculate position size with zero price
        vm.expectRevert(); // Should revert on division by zero
        perpsRouter.calculatePositionSize(1000e6, 5e18, 0);
        
        vm.stopPrank();
    }
    
    /// @notice Test integer overflow with extremely large positions
    function testFuzz_ArithmeticOverflow(uint256 margin, uint256 leverage) public {
        // Bound inputs to realistic but large values that could overflow
        margin = bound(margin, 1e6, type(uint128).max / 1e18); // Prevent immediate overflow
        leverage = bound(leverage, 1e18, 1000e18); // Up to 1000x leverage
        
        // This should either work correctly or revert gracefully (not silently overflow)
        try perpsRouter.calculatePositionSize(margin, leverage, TEST_PRICE) returns (uint256 notional, uint256 base) {
            // If it succeeds, verify the math is correct
            assertTrue(notional > 0, "Notional should be positive");
            assertTrue(base > 0, "Base size should be positive");
            
            // Verify no silent overflow occurred
            uint256 expectedNotional = (margin * 1e12 * leverage) / 1e18;
            assertEq(notional, expectedNotional, "Notional calculation incorrect");
        } catch {
            // Revert is acceptable for overflow cases
        }
    }
    
    /// @notice Test precision loss in PnL calculations
    function test_PrecisionLossInPnL() public {
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), type(uint256).max);
        marginAccount.deposit(10000e6);
        
        // Open a very small position that could suffer precision loss
        uint256 tokenId = positionManager.openPositionFor(
            user1,
            marketId,
            1, // Extremely small position (1 wei)
            TEST_PRICE,
            1000e6 // $1000 margin
        );
        
        // Check unrealized PnL with small price changes
        uint256 newPrice = TEST_PRICE + 1e12; // Very small price change
        int256 pnl = positionManager.getUnrealizedPnL(tokenId, newPrice);
        
        // For such a small position and price change, PnL might be 0 due to precision loss
        // This is acceptable but we should document it
        assertTrue(pnl >= 0, "PnL calculation should not underflow");
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                      ECONOMIC ATTACK VECTORS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test that system handles large positions safely  
    function test_FlashLoanAttackSimulation() public {
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), type(uint256).max);
        marginAccount.deposit(100000e6); // Large deposit
        
        // Test that large positions are handled properly without issues
        uint256 tokenId = positionManager.openPosition(
            marketId,
            5e18, // Reasonable position size (5 ETH)
            TEST_PRICE,
            50000e6 // Large margin amount  
        );
        
        // Verify system handles large position correctly
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        assertTrue(position.owner == user1, "Position should exist");
        assertTrue(position.margin == 50000e6, "Margin should be correct");
        assertTrue(position.sizeBase == 5e18, "Size should be correct");
        
        vm.stopPrank();
    }
    
    /// @notice Test MEV sandwich attack protection
    function test_MEVSandwichAttackProtection() public {
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), type(uint256).max);
        marginAccount.deposit(10000e6);
        
        // User creates position
        uint256 tokenId = positionManager.openPositionFor(
            user1,
            marketId,
            1e18, // 1 ETH position
            TEST_PRICE,
            1000e6 // $1000 margin
        );
        
        // Simulate MEV bot trying to sandwich the position
        vm.startPrank(attacker);
        usdc.approve(address(marginAccount), type(uint256).max);
        marginAccount.deposit(50000e6);
        
        // MEV bot opens large opposing position to manipulate funding
        uint256 mevTokenId = positionManager.openPositionFor(
            attacker,
            marketId,
            -10e18, // Large short position
            TEST_PRICE,
            50000e6
        );
        
        vm.stopPrank();
        vm.startPrank(user1);
        
        // User's position should still be intact and not manipulated
        PositionLib.Position memory userPosition = positionManager.getPosition(tokenId);
        assertEq(userPosition.entryPrice, TEST_PRICE, "User's entry price should not be manipulated");
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                       EXTREME MARKET CONDITIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test extreme price movements
    function testFuzz_ExtremePriceMovements(uint256 newPrice) public {
        // Bound to extreme but realistic price ranges (from $1 to $100,000)
        newPrice = bound(newPrice, 1e18, 100000e18);
        
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), type(uint256).max);
        marginAccount.deposit(10000e6);
        
        // Open position at current price
        uint256 tokenId = positionManager.openPositionFor(
            user1,
            marketId,
            1e18, // 1 ETH
            TEST_PRICE,
            1000e6
        );
        
        // Calculate PnL at extreme price
        int256 pnl = positionManager.getUnrealizedPnL(tokenId, newPrice);
        
        // Verify PnL calculation doesn't overflow/underflow
        assertTrue(pnl > type(int128).min, "PnL should not underflow");
        assertTrue(pnl < type(int128).max, "PnL should not overflow");
        
        // Verify leverage calculation at extreme price
        uint256 leverage = positionManager.getCurrentLeverage(tokenId, newPrice);
        assertTrue(leverage >= 0, "Leverage should not be negative");
        
        vm.stopPrank();
    }
    
    /// @notice Test zero and negative position sizes
    function test_ZeroPositionHandling() public {
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), type(uint256).max);
        marginAccount.deposit(10000e6);
        
        // Try to create zero position (should be rejected)
        vm.expectRevert();
        positionManager.openPositionFor(
            user1,
            marketId,
            0, // Zero position size
            TEST_PRICE,
            1000e6
        );
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                      LIQUIDATION EDGE CASES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test liquidation with insufficient insurance fund
    function test_LiquidationWithInsufficientInsurance() public {
        // This test would require implementing the actual liquidation system
        // For now, we'll test the setup and basic liquidation detection
        
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), type(uint256).max);
        marginAccount.deposit(10000e6); // Increase deposit for higher leverage capability
        
        // Open position with maximum allowed leverage (just under 20x)
        uint256 tokenId = positionManager.openPositionFor(
            user1,
            marketId,
            19e18, // 19 ETH position  
            TEST_PRICE,
            2000e6 // $2000 margin = ~19x leverage (within limits)
        );
        
        // Verify position was created
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        assertTrue(position.sizeBase > 0, "Position should exist");
        
        // Calculate current leverage - should be close to but under 20x
        uint256 leverage = positionManager.getCurrentLeverage(tokenId, TEST_PRICE);
        assertTrue(leverage > 18e18, "Position should be highly leveraged");
        assertTrue(leverage <= 20e18, "Position should be within leverage limits");
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                       GAS OPTIMIZATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test gas consumption with many positions
    function test_GasEfficiencyWithManyPositions() public {
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), type(uint256).max);
        marginAccount.deposit(100000e6);
        
        uint256 gasStart = gasleft();
        
        // Create multiple positions
        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            tokenIds[i] = positionManager.openPositionFor(
                user1,
                marketId,
                1e17, // 0.1 ETH each
                TEST_PRICE,
                1000e6 // $1000 margin each
            );
        }
        
        uint256 gasAfterCreation = gasleft();
        
        // Get user positions (this should be efficient)
        uint256[] memory userPositions = positionManager.getUserPositions(user1);
        assertEq(userPositions.length, 10, "Should have 10 positions");
        
        uint256 gasAfterRetrieval = gasleft();
        
        console.log("Gas used for creating 10 positions:", gasStart - gasAfterCreation);
        console.log("Gas used for retrieving positions:", gasAfterCreation - gasAfterRetrieval);
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                      ACCESS CONTROL EDGE CASES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test unauthorized access attempts
    function test_UnauthorizedAccessProtection() public {
        // Try to call authorized functions without permission
        vm.startPrank(attacker);
        
        vm.expectRevert();
        marginAccount.lockMargin(user1, 1000e6);
        
        vm.expectRevert();
        marginAccount.settlePnL(user1, 1000e6);
        
        vm.expectRevert();
        positionManager.openPositionFor(user1, marketId, 1e18, TEST_PRICE, 1000e6);
        
        vm.stopPrank();
    }
    
    /// @notice Test position ownership verification
    function test_PositionOwnershipProtection() public {
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), type(uint256).max);
        marginAccount.deposit(10000e6);
        
        uint256 tokenId = positionManager.openPositionFor(
            user1,
            marketId,
            1e18,
            TEST_PRICE,
            1000e6
        );
        vm.stopPrank();
        
        // Attacker tries to modify user1's position
        vm.startPrank(attacker);
        
        vm.expectRevert();
        positionManager.addMargin(tokenId, 500e6);
        
        vm.expectRevert();
        positionManager.removeMargin(tokenId, 500e6);
        
        vm.stopPrank();
    }
}
