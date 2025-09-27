// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {PositionLib} from "../src/libraries/PositionLib.sol";
import {PositionFactory} from "../src/PositionFactory.sol";
import {PositionNFT} from "../src/PositionNFT.sol";
import {MarketManager} from "../src/MarketManager.sol";
import {PositionManager} from "../src/PositionManagerV2.sol";
import {MarginAccount} from "../src/MarginAccount.sol";
import {MockUSDC} from "../test/utils/mocks/MockUSDC.sol";
import {MockVETH} from "../test/utils/mocks/MockVETH.sol";

contract PositionManagerTest is Test {
    // Modular system components
    PositionManager public positionManager;
    PositionFactory public positionFactory;
    PositionNFT public positionNFT;
    MarketManager public marketManager;
    MarginAccount public marginAccount;
    MockUSDC public usdc;
    MockVETH public veth;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public poolAddress = address(0x123);

    bytes32 public constant ETH_USDC_MARKET = keccak256("ETH-USDC");
    
    // Test constants
    uint256 public constant INITIAL_USDC_SUPPLY = 1_000_000 * 1e6; // 1M USDC
    uint256 public constant INITIAL_VETH_SUPPLY = 1_000 * 1e18;    // 1K vETH
    uint256 public constant ETH_PRICE = 2000 * 1e18;               // $2000 ETH (1e18 precision)
    
    // Position test constants - adjusted for proper leverage
    uint256 public constant TEST_MARGIN = 1000 * 1e6;              // 1000 USDC margin
    int256 public constant TEST_ETH_SIZE = 1e17;                   // 0.1 ETH position for 2x leverage
    uint256 public constant LARGE_MARGIN = 2000 * 1e6;             // 2000 USDC for larger tests
    
    function setUp() public {
        // Deploy mock tokens
        usdc = new MockUSDC();
        veth = new MockVETH();
        
        // Deploy modular system components
        marginAccount = new MarginAccount(address(usdc));
        positionFactory = new PositionFactory(address(usdc), address(marginAccount));
        positionNFT = new PositionNFT();
        marketManager = new MarketManager();
        positionManager = new PositionManager(
            address(positionFactory),
            address(positionNFT),
            address(marketManager)
        );
        
        // Configure relationships between components
        positionNFT.setFactory(address(positionFactory));
        positionFactory.setPositionNFT(address(positionNFT));
        marginAccount.addAuthorizedContract(address(positionFactory));
        
        // Mint initial tokens
        usdc.mint(owner, INITIAL_USDC_SUPPLY);
        usdc.mint(user1, INITIAL_USDC_SUPPLY);
        usdc.mint(user2, INITIAL_USDC_SUPPLY);
        
        veth.mint(owner, INITIAL_VETH_SUPPLY);
        
        // Add ETH/USDC market using the modular system
        marketManager.addMarket(
            ETH_USDC_MARKET,
            address(veth),
            address(usdc),
            poolAddress
        );
        
        positionFactory.addMarket(
            ETH_USDC_MARKET,
            address(veth),
            address(usdc),
            poolAddress
        );
        
        // Approve USDC spending for users and deposit into MarginAccount
        vm.prank(user1);
        usdc.approve(address(marginAccount), type(uint256).max);
        vm.prank(user1);
        marginAccount.deposit(100000 * 1e6); // Deposit 100k USDC for user1
        
        vm.prank(user2);
        usdc.approve(address(marginAccount), type(uint256).max);
        vm.prank(user2);
        marginAccount.deposit(100000 * 1e6); // Deposit 100k USDC for user2
        
        // Fund the PositionFactory with extra USDC to simulate liquidity pool for profits
        usdc.mint(address(positionFactory), 100000 * 1e6); // 100k USDC for covering profits
    }

    /*//////////////////////////////////////////////////////////////
                        MARKET MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AddMarket() public {
        bytes32 newMarketId = keccak256("BTC-USDC");
        
        marketManager.addMarket(
            newMarketId,
            address(0x456), // Mock BTC address
            address(usdc),
            address(0x789)  // Mock pool address
        );
        
        positionFactory.addMarket(
            newMarketId,
            address(0x456), // Mock BTC address
            address(usdc),
            address(0x789)  // Mock pool address
        );
        
        PositionLib.Market memory market = marketManager.getMarket(newMarketId);
        assertEq(market.baseAsset, address(0x456));
        assertEq(market.quoteAsset, address(usdc));
        assertEq(market.poolAddress, address(0x789));
        assertTrue(market.isActive);
        assertEq(market.fundingIndex, 1e18);
    }

    function test_SetMarketStatus() public {
        // Market status functionality removed for size optimization
        // marketManager.setMarketStatus(ETH_USDC_MARKET, false);
        
        PositionLib.Market memory market = marketManager.getMarket(ETH_USDC_MARKET);
        // assertFalse(market.isActive);
        
        // marketManager.setMarketStatus(ETH_USDC_MARKET, true);
        // market = marketManager.getMarket(ETH_USDC_MARKET);
        assertTrue(market.isActive);
    }

    /*//////////////////////////////////////////////////////////////
                        POSITION OPENING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_OpenLongPosition() public {
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_ETH_SIZE,
            ETH_PRICE,
            TEST_MARGIN
        );
        
        // Verify position data
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        assertEq(position.owner, user1);
        assertEq(position.marketId, ETH_USDC_MARKET);
        assertEq(position.sizeBase, TEST_ETH_SIZE);
        assertEq(position.entryPrice, ETH_PRICE);
        assertEq(position.margin, TEST_MARGIN);
        assertEq(position.lastFundingIndex, 1e18);
        assertGt(position.openedAt, 0);
        
        // Verify NFT ownership
        assertEq(positionManager.ownerOf(tokenId), user1);
        assertEq(positionManager.balanceOf(user1), 1);
        
        // Verify user positions tracking
        uint256[] memory userPositions = positionManager.getUserPositions(user1);
        assertEq(userPositions.length, 1);
        assertEq(userPositions[0], tokenId);
        
        // Verify market positions tracking
        uint256[] memory marketPositions = positionManager.getMarketPositions(ETH_USDC_MARKET);
        assertEq(marketPositions.length, 1);
        assertEq(marketPositions[0], tokenId);
    }

    function test_OpenShortPosition() public {
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            -TEST_ETH_SIZE,
            ETH_PRICE,
            TEST_MARGIN
        );
        
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        assertEq(position.sizeBase, -TEST_ETH_SIZE);
        assertTrue(position.sizeBase < 0); // Verify it's a short position
    }

    function test_RevertOpenPosition_InsufficientMargin() public {
        uint256 margin = 5 * 1e6;   // 5 USDC (below minimum)
        int256 size = 1 * 1e18;     // 1 ETH
        
        vm.prank(user1);
        vm.expectRevert(PositionLib.InsufficientMargin.selector);
        positionManager.openPosition(ETH_USDC_MARKET, size, ETH_PRICE, margin);
    }

    function test_RevertOpenPosition_ExceedsMaxLeverage() public {
        uint256 margin = 1000 * 1e6;  // 1000 USDC (sufficient margin)
        int256 size = 25 * 1e18;       // 25 ETH (50x leverage with 2000 price, exceeds max 20x)
        
        vm.prank(user1);
        vm.expectRevert(PositionLib.ExceedsMaxLeverage.selector);
        positionManager.openPosition(ETH_USDC_MARKET, size, ETH_PRICE, margin);
    }

    function test_RevertOpenPosition_MarketNotActive() public {
        // Market deactivation functionality removed for size optimization
        // positionManager.setMarketStatus(ETH_USDC_MARKET, false);
        
        // This test is now obsolete since market status cannot be changed
        // vm.prank(user1);
        // vm.expectRevert(PositionManager.MarketNotActive.selector);
        // positionManager.openPosition(ETH_USDC_MARKET, TEST_ETH_SIZE, ETH_PRICE, TEST_MARGIN);
    }

    /*//////////////////////////////////////////////////////////////
                        POSITION CLOSING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ClosePositionProfit() public {
        // Open long position at $2000
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_ETH_SIZE,
            ETH_PRICE,
            TEST_MARGIN
        );
        
        uint256 initialMarginBalance = marginAccount.getAvailableBalance(user1);
        
        // Close position at $2200 (profit)
        uint256 exitPrice = 2200 * 1e18;
        vm.prank(user1);
        positionManager.closePosition(tokenId, exitPrice);
        
        // Check NFT was burned
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        positionManager.ownerOf(tokenId);
        
        // Check profit was paid out to MarginAccount
        uint256 finalMarginBalance = marginAccount.getAvailableBalance(user1);
        // Expected profit: 0.1 ETH * $200 price diff = $20 = 20e6 USDC
        uint256 expectedProfit = 20e6;
        assertEq(finalMarginBalance, initialMarginBalance + TEST_MARGIN + expectedProfit);
    }

    function test_ClosePositionLoss() public {
        // Open long position at $2000
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_ETH_SIZE,
            ETH_PRICE,
            TEST_MARGIN
        );
        
        uint256 initialMarginBalance = marginAccount.getAvailableBalance(user1);
        
        // Close position at $1800 (loss)
        uint256 exitPrice = 1800 * 1e18;
        vm.prank(user1);
        positionManager.closePosition(tokenId, exitPrice);
        
        // Check loss was deducted from MarginAccount
        uint256 finalMarginBalance = marginAccount.getAvailableBalance(user1);
        // Expected loss: 0.1 ETH * $200 price diff = $20 = 20e6 USDC
        uint256 expectedLoss = 20e6;
        assertEq(finalMarginBalance, initialMarginBalance + TEST_MARGIN - expectedLoss);
    }

    /*//////////////////////////////////////////////////////////////
                        MARGIN MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AddMargin() public {
        // Open position
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_ETH_SIZE,
            ETH_PRICE,
            TEST_MARGIN
        );
        
        // Add margin
        uint256 additionalMargin = 500e6;
        vm.prank(user1);
        positionManager.addMargin(tokenId, additionalMargin);
        
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        assertEq(position.margin, TEST_MARGIN + additionalMargin);
    }

    function test_RemoveMargin() public {
        // Open position with larger margin
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_ETH_SIZE,
            ETH_PRICE,
            LARGE_MARGIN
        );
        
        uint256 initialMarginBalance = marginAccount.getAvailableBalance(user1);
        
        // Remove some margin
        uint256 marginToRemove = 500e6;
        vm.prank(user1);
        positionManager.removeMargin(tokenId, marginToRemove);
        
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        assertEq(position.margin, LARGE_MARGIN - marginToRemove);
        
        // Check margin was returned to MarginAccount
        uint256 finalMarginBalance = marginAccount.getAvailableBalance(user1);
        assertEq(finalMarginBalance, initialMarginBalance + marginToRemove);
    }

    function test_RevertRemoveMargin_BelowMinimum() public {
        // Open position with minimum margin
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_ETH_SIZE,
            ETH_PRICE,
            TEST_MARGIN
        );
        
        // Try to remove margin that would go below minimum
        vm.prank(user1);
        vm.expectRevert(PositionLib.InsufficientMargin.selector);
        positionManager.removeMargin(tokenId, 995e6);
    }

    /*//////////////////////////////////////////////////////////////
                        PNL CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetUnrealizedPnL_Long() public {
        // Open long position at $2000
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_ETH_SIZE,
            ETH_PRICE,
            TEST_MARGIN
        );
        
        // Check PnL at $2200 (profit)
        int256 pnl = positionManager.getUnrealizedPnL(tokenId, 2200e18);
        // Expected: 0.1 ETH * $200 price diff = $20 = 20e18 (in 18 decimals)
        assertEq(pnl, 20e18);
        
        // Check PnL at $1800 (loss)
        pnl = positionManager.getUnrealizedPnL(tokenId, 1800e18);
        // Expected: 0.1 ETH * -$200 price diff = -$20 = -20e18 (in 18 decimals)
        assertEq(pnl, -20e18);
    }

    function test_GetUnrealizedPnL_Short() public {
        // Open short position at $2000
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            -TEST_ETH_SIZE,
            ETH_PRICE,
            TEST_MARGIN
        );
        
        // Check PnL at $1800 (profit for short)
        int256 pnl = positionManager.getUnrealizedPnL(tokenId, 1800e18);
        // Expected: -0.1 ETH * -$200 price diff = $20 = 20e18 (in 18 decimals)
        assertEq(pnl, 20e18);
        
        // Check PnL at $2200 (loss for short)
        pnl = positionManager.getUnrealizedPnL(tokenId, 2200e18);
        // Expected: -0.1 ETH * $200 price diff = -$20 = -20e18 (in 18 decimals)
        assertEq(pnl, -20e18);
    }

    /*//////////////////////////////////////////////////////////////
                        LEVERAGE CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetCurrentLeverage() public {
        // Open position: 0.1 ETH with 1000 USDC margin at $2000
        // Initial leverage: 200 / 1000 = 0.2x
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_ETH_SIZE,
            ETH_PRICE,
            TEST_MARGIN
        );
        
        uint256 leverage = positionManager.getCurrentLeverage(tokenId, ETH_PRICE);
        // Expected: (0.1 ETH * 2000 USD/ETH) / 1000 USD = 0.2x = 0.2e18
        assertEq(leverage, 0.2e18); 
        
        // Check leverage at different price ($3000)
        leverage = positionManager.getCurrentLeverage(tokenId, 3000e18);
        // Expected: (0.1 ETH * 3000 USD/ETH) / 1000 USD = 0.3x = 0.3e18
        assertEq(leverage, 0.3e18);
    }

    /*//////////////////////////////////////////////////////////////
                        FUNDING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_UpdateFundingIndex() public {
        uint256 newFundingIndex = 1.1e18; // 10% funding rate
        
        marketManager.updateFundingIndex(ETH_USDC_MARKET, newFundingIndex);
        positionFactory.updateFundingIndex(ETH_USDC_MARKET, newFundingIndex);
        
        PositionLib.Market memory market = marketManager.getMarket(ETH_USDC_MARKET);
        assertEq(market.fundingIndex, newFundingIndex);
        assertEq(market.lastFundingUpdate, block.timestamp);
    }

    function test_SettleFunding() public {
        // Open position
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_ETH_SIZE,
            ETH_PRICE,
            TEST_MARGIN
        );
        
        // Update funding index
        uint256 newFundingIndex = 1.1e18;
        marketManager.updateFundingIndex(ETH_USDC_MARKET, newFundingIndex);
        positionFactory.updateFundingIndex(ETH_USDC_MARKET, newFundingIndex);
        
        // Funding settlement now handled automatically in position updates
        // positionManager.settleFunding(tokenId);
        
        // To trigger funding settlement, we need to update or close the position as the owner
        vm.prank(user1);
        positionManager.updatePosition(tokenId, TEST_ETH_SIZE, TEST_MARGIN);
        
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        assertEq(position.lastFundingIndex, newFundingIndex);
        
        // Funding payment = size * indexDiff / 1e18 = 0.1e18 * 0.1e18 / 1e18 = 0.01e18
        assertEq(position.fundingPaid, (TEST_ETH_SIZE * 0.1e18) / 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertNonOwner_AddMarket() public {
        vm.prank(user1);
        vm.expectRevert();
        marketManager.addMarket(
            keccak256("TEST"),
            address(veth),
            address(usdc),
            address(0x123)
        );
    }

    function test_RevertNonOwner_SetMarketStatus() public {
        // Market status functionality removed for size optimization
        // vm.prank(user1);
        // vm.expectRevert();
        // positionManager.setMarketStatus(ETH_USDC_MARKET, false);
    }

    function test_RevertNonPositionOwner_ClosePosition() public {
        // User1 opens position
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_ETH_SIZE,
            ETH_PRICE,
            TEST_MARGIN
        );
        
        // User2 tries to close it
        vm.prank(user2);
        vm.expectRevert(PositionLib.NotPositionOwner.selector);
        positionManager.closePosition(tokenId, ETH_PRICE);
    }

    /*//////////////////////////////////////////////////////////////
                        ENUMERATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_PositionEnumeration() public {
        // Open multiple positions for different users
        vm.prank(user1);
        positionManager.openPosition(ETH_USDC_MARKET, TEST_ETH_SIZE, ETH_PRICE, TEST_MARGIN);
        
        vm.prank(user1);
        positionManager.openPosition(ETH_USDC_MARKET, -TEST_ETH_SIZE, ETH_PRICE, TEST_MARGIN);
        
        vm.prank(user2);
        uint256 tokenId3 = positionManager.openPosition(ETH_USDC_MARKET, TEST_ETH_SIZE * 2, ETH_PRICE, LARGE_MARGIN);
        
        // Check total supply
        assertEq(positionManager.totalSupply(), 3);
        
        // Check user positions
        uint256[] memory user1Positions = positionManager.getUserPositions(user1);
        assertEq(user1Positions.length, 2);
        
        uint256[] memory user2Positions = positionManager.getUserPositions(user2);
        assertEq(user2Positions.length, 1);
        assertEq(user2Positions[0], tokenId3);
        
        // Check market positions
        uint256[] memory marketPositions = positionManager.getMarketPositions(ETH_USDC_MARKET);
        assertEq(marketPositions.length, 3);
    }
}
