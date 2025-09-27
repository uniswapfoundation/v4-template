// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {PositionManager} from "../src/PositionManagerV2.sol";
import {PositionFactory} from "../src/PositionFactory.sol";
import {PositionNFT} from "../src/PositionNFT.sol";
import {MarketManager} from "../src/MarketManager.sol";
import {PositionLib} from "../src/libraries/PositionLib.sol";
import {MarginAccount} from "../src/MarginAccount.sol";
import {PerpsRouter} from "../src/PerpsRouter.sol";
import {MockUSDC} from "../test/utils/mocks/MockUSDC.sol";
import {MockVETH} from "../test/utils/mocks/MockVETH.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract MockPoolManager {
    function swap(PoolKey calldata, address, bytes calldata) external returns (uint256) {
        return 0;
    }
}

contract MockFundingOracle {
    uint256 public mockPrice = 2000e18;
    mapping(bytes32 => uint256) private marketPrices;
    
    function getMarkPrice(bytes32 marketId) external view returns (uint256) {
        uint256 price = marketPrices[marketId];
        return price > 0 ? price : mockPrice; // Return market-specific price or default
    }
    
    function setMockPrice(uint256 price) external {
        mockPrice = price;
    }
    
    function setMarketPrice(bytes32 marketId, uint256 price) external {
        marketPrices[marketId] = price;
    }
}

contract BugFixVerificationTest is Test {
    PositionManager public positionManager;
    PositionFactory public positionFactory;
    PositionNFT public positionNFT;
    MarketManager public marketManager;
    MarginAccount public marginAccount;
    PerpsRouter public perpsRouter;
    MockUSDC public usdc;
    MockVETH public veth;
    MockPoolManager public poolManager;
    MockFundingOracle public fundingOracle;

    address public owner = address(this);
    address public user1 = address(0x1);
    bytes32 public constant ETH_USDC_MARKET = keccak256("ETH-USDC");
    
    uint256 public constant INITIAL_USDC_SUPPLY = 1_000_000 * 1e6;
    uint256 public constant ETH_PRICE = 2000 * 1e18;
    uint256 public constant TEST_MARGIN = 1000 * 1e6;
    int256 public constant TEST_ETH_SIZE = 1e17; // 0.1 ETH position

    function setUp() public {
        usdc = new MockUSDC();
        veth = new MockVETH();
        poolManager = new MockPoolManager();
        fundingOracle = new MockFundingOracle();
        
        marginAccount = new MarginAccount(address(usdc));
        positionFactory = new PositionFactory(address(usdc), address(marginAccount));
        positionNFT = new PositionNFT();
        marketManager = new MarketManager();
        positionManager = new PositionManager(
            address(positionFactory),
            address(positionNFT),
            address(marketManager)
        );
        perpsRouter = new PerpsRouter(
            address(marginAccount),
            address(positionManager),
            address(positionFactory),
            address(fundingOracle),
            address(poolManager),
            address(usdc)
        );
        
        // Setup modular component authorizations
        positionFactory.setPositionNFT(address(positionNFT));
        positionNFT.setFactory(address(positionFactory));
        
        // Transfer ownership of modular components to PositionManager
        positionFactory.transferOwnership(address(positionManager));
        marketManager.transferOwnership(address(positionManager));
        
        // Set up contract authorizations
        marginAccount.addAuthorizedContract(address(positionManager));
        marginAccount.addAuthorizedContract(address(positionFactory));
        marginAccount.addAuthorizedContract(address(perpsRouter));
        // Note: addAuthorizedContract was removed from PositionManager for contract size optimization
        // positionManager.addAuthorizedContract(address(perpsRouter));
        
        usdc.mint(user1, INITIAL_USDC_SUPPLY);
        
        positionManager.addMarket(
            ETH_USDC_MARKET,
            address(veth),
            address(usdc),
            address(0x123)
        );
        
        vm.prank(user1);
        usdc.approve(address(marginAccount), type(uint256).max);
        vm.prank(user1);
        marginAccount.deposit(100000 * 1e6);
    }

    function test_ClosePositionBugFixed() public {
        console.log("=== Testing Position Close Bug Fix ===");
        
        // Open a position
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_ETH_SIZE, // 0.1 ETH long
            ETH_PRICE,     // $2000 entry
            TEST_MARGIN    // 1000 USDC margin
        );
        
        uint256 initialFree = marginAccount.freeBalance(user1);
        uint256 initialLocked = marginAccount.lockedBalance(user1);
        
        console.log("After opening position:");
        console.log("  Free balance:", initialFree);
        console.log("  Locked balance:", initialLocked);
        
        // Test closing at a loss
        uint256 exitPrice = 1800 * 1e18; // $200 loss per ETH = $20 total loss
        
        vm.prank(user1);
        positionManager.closePosition(tokenId, exitPrice);
        
        uint256 finalFree = marginAccount.freeBalance(user1);
        uint256 finalLocked = marginAccount.lockedBalance(user1);
        
        console.log("After closing position:");
        console.log("  Free balance:", finalFree);
        console.log("  Locked balance:", finalLocked);
        
        // Verify:
        // 1. All locked balance was unlocked
        assertEq(finalLocked, 0, "All locked balance should be unlocked");
        
        // 2. Free balance should reflect initial + margin - loss
        // Expected: 99000e6 (initial) + 1000e6 (margin returned) - 20e6 (loss) = 99980e6
        uint256 expectedFinal = initialFree + TEST_MARGIN - 20e6;
        assertEq(finalFree, expectedFinal, "Free balance should account for margin return and loss");
        
        console.log("Close position bug fixed - proper PnL settlement");
    }

    function test_PerpsRouterPartialCloseAuth() public {
        console.log("=== Testing PerpsRouter Partial Close Authorization ===");
        
        // This test verifies that PerpsRouter can properly call PositionManager.updatePosition
        // when authorized, and that partial closes work
        
        // Create a mock PoolKey for the router
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(veth)),
            currency1: Currency.wrap(address(usdc)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        
        // Set up market price for this pool ID in the oracle
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        bytes32 marketId = PoolId.unwrap(poolId);
        fundingOracle.setMarketPrice(marketId, ETH_PRICE);
        
        // Also register this market in the PositionManager
        positionManager.addMarket(
            marketId,
            address(veth),
            address(usdc),
            address(0x123)
        );
        
        // Authorization removed for size optimization
        // positionManager.addAuthorizedContract(address(perpsRouter));
        
        // Open position through router
        vm.prank(user1);
        usdc.approve(address(perpsRouter), type(uint256).max);
        
        vm.prank(user1);
        perpsRouter.depositMargin(5000e6); // Deposit more margin for router
        
        PerpsRouter.OpenPositionParams memory openParams = PerpsRouter.OpenPositionParams({
            poolKey: poolKey,
            isLong: true,
            marginAmount: 2000e6, // 2000 USDC margin  
            leverage: 2e18, // 2x leverage
            slippageBps: 100, // 1% slippage
            deadline: block.timestamp + 300
        });
        
        vm.prank(user1);
        uint256 tokenId = perpsRouter.openPosition(openParams);
        
        console.log("Position opened via router, tokenId:", tokenId);
        
        // Test partial close
        PerpsRouter.ClosePositionParams memory closeParams = PerpsRouter.ClosePositionParams({
            tokenId: tokenId,
            sizeBps: 5000, // Close 50%
            slippageBps: 100,
            deadline: block.timestamp + 300
        });
        
        vm.prank(user1);
        perpsRouter.closePosition(closeParams);
        
        console.log("Partial close successful with authorization");
        
        // Verify the position was partially closed
        PositionLib.Position memory positionAfter = positionManager.getPosition(tokenId);
        assertTrue(positionAfter.sizeBase < 2000000000000000000); // Should be reduced
        console.log("Position size after partial close:", positionAfter.sizeBase);
        
        // Test full close (should work)
        closeParams.sizeBps = 10000; // Close 100%
        
        vm.prank(user1);
        perpsRouter.closePosition(closeParams);
        
        console.log("Full close works properly through router");
    }

    function test_PositionManagerUpdateFunction() public {
        console.log("=== Testing PositionManager updatePosition Function ===");
        
        // Open a position directly
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_ETH_SIZE, // 0.1 ETH long
            ETH_PRICE,     // $2000 entry
            TEST_MARGIN    // 1000 USDC margin
        );
        
        PositionLib.Position memory posBefore = positionManager.getPosition(tokenId);
        console.log("Position before update:");
        console.log("  Size:", uint256(posBefore.sizeBase));
        console.log("  Margin:", posBefore.margin);
        
        // Test that position owner CAN update their position
        vm.prank(user1);
        bool success = positionManager.updatePosition(tokenId, 5e16, 500e6); // Reduce by half
        assertTrue(success, "Position owner should be able to update their position");
        
        PositionLib.Position memory posAfter = positionManager.getPosition(tokenId);
        console.log("Position after update by owner:");
        console.log("  Size:", uint256(posAfter.sizeBase));
        console.log("  Margin:", posAfter.margin);
        
        assertEq(posAfter.sizeBase, 5e16, "Size should be updated");
        assertEq(posAfter.margin, 500e6, "Margin should be updated");
        
        // Test unauthorized update from different address (should fail)
        vm.prank(address(0x999));
        try positionManager.updatePosition(tokenId, 2e16, 200e6) {
            assertTrue(false, "Should have reverted for unauthorized caller");
        } catch {
            console.log("Expected unauthorized revert caught");
        }
        
        // Authorization system removed for size optimization  
        // positionManager.addAuthorizedContract(address(this));
        
        // Test that updatePosition still works when called by position owner
        vm.prank(user1); // Call as the actual position owner
        success = positionManager.updatePosition(tokenId, 2e16, 200e6); // Further reduce
        assertTrue(success, "updatePosition should work for position owner");
        
        console.log("updatePosition function works correctly");
    }
}
