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
import {MockUSDC} from "../test/utils/mocks/MockUSDC.sol";
import {MockVETH} from "../test/utils/mocks/MockVETH.sol";

contract DebugClosePositionTest is Test {
    PositionManager public positionManager;
    PositionFactory public positionFactory;
    PositionNFT public positionNFT;
    MarketManager public marketManager;
    MarginAccount public marginAccount;
    MockUSDC public usdc;
    MockVETH public veth;

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
        
        marginAccount = new MarginAccount(address(usdc));
        positionFactory = new PositionFactory(address(usdc), address(marginAccount));
        positionNFT = new PositionNFT();
        marketManager = new MarketManager();
        positionManager = new PositionManager(
            address(positionFactory),
            address(positionNFT),
            address(marketManager)
        );
        
        // Setup modular component authorizations
        positionFactory.setPositionNFT(address(positionNFT));
        positionNFT.setFactory(address(positionFactory));
        
        // Transfer ownership of modular components to PositionManager
        positionFactory.transferOwnership(address(positionManager));
        marketManager.transferOwnership(address(positionManager));
        
        marginAccount.addAuthorizedContract(address(positionManager));
        marginAccount.addAuthorizedContract(address(positionFactory));
        
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

    function test_DetectClosePositionBug() public {
        // Open a position with a large loss scenario
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_ETH_SIZE, // 0.1 ETH long
            ETH_PRICE,     // $2000 entry
            TEST_MARGIN    // 1000 USDC margin
        );
        
        console.log("Position opened with tokenId:", tokenId);
        console.log("Initial free balance:", marginAccount.freeBalance(user1));
        console.log("Initial locked balance:", marginAccount.lockedBalance(user1));
        
        // Check position before closing
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        console.log("Position margin:", position.margin);
        console.log("Position size:", uint256(position.sizeBase));
        
        // Try to close position at a big loss ($2000 -> $1000 = $100 loss on 0.1 ETH)
        uint256 exitPrice = 1000 * 1e18; // Massive loss
        
        // This should cause issues with the PnL settlement
        vm.prank(user1);
        try positionManager.closePosition(tokenId, exitPrice) {
            console.log("Position closed successfully");
            console.log("Final free balance:", marginAccount.freeBalance(user1));
            console.log("Final locked balance:", marginAccount.lockedBalance(user1));
        } catch Error(string memory reason) {
            console.log("Failed to close position:", reason);
        } catch (bytes memory) {
            console.log("Failed to close position with low-level error");
        }
    }

    function test_DeepDebugClosePosition() public {
        // Open position
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_ETH_SIZE,
            ETH_PRICE,
            TEST_MARGIN
        );
        
        uint256 initialFree = marginAccount.freeBalance(user1);
        uint256 initialLocked = marginAccount.lockedBalance(user1);
        
        console.log("=== Before Close ===");
        console.log("Free balance:", initialFree);
        console.log("Locked balance:", initialLocked);
        
        // Simulate a large loss
        uint256 exitPrice = 1800 * 1e18; // $200 loss per ETH
        // Expected loss: 0.1 ETH * $200 = $20 = 20e6 USDC
        
        // Step by step debug what should happen:
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        
        // Calculate PnL manually
        int256 priceDiff = int256(exitPrice) - int256(position.entryPrice);
        int256 expectedPnL = (position.sizeBase * priceDiff) / 1e18;
        expectedPnL = expectedPnL / 1e12; // Convert to 6 decimals
        
        console.log("Expected PnL (should be negative):", expectedPnL);
        console.log("Position margin:", position.margin);
        
        if (expectedPnL < 0) {
            uint256 loss = uint256(-expectedPnL);
            console.log("Loss amount:", loss);
            
            // What should happen in settlePnL:
            // 1. Loss deducted from locked balance first
            uint256 remainingMargin = position.margin;
            if (loss >= position.margin) {
                remainingMargin = 0;
                console.log("All margin consumed by loss");
            } else {
                remainingMargin = position.margin - loss;
                console.log("Remaining margin after loss:", remainingMargin);
            }
        }
        
        // Now actually close and see what happens
        vm.prank(user1);
        positionManager.closePosition(tokenId, exitPrice);
        
        console.log("=== After Close ===");
        console.log("Free balance:", marginAccount.freeBalance(user1));
        console.log("Locked balance:", marginAccount.lockedBalance(user1));
    }
}
